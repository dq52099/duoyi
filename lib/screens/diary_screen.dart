import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/diary_entry.dart';
import '../providers/diary_provider.dart';
import '../core/lunar_calendar.dart';
import '../widgets/empty_state.dart';
import '../widgets/mood_heatmap.dart';
import '../widgets/surface_components.dart';

class DiaryScreen extends StatelessWidget {
  const DiaryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DiaryProvider>();
    final entries = provider.entries;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('日记'),
        actions: [
          IconButton(
            icon: const Icon(Icons.insights),
            tooltip: '心情统计',
            onPressed: () => _showMoodStats(context, provider),
          ),
        ],
      ),
      body: entries.isEmpty
          ? EmptyState(
              icon: Icons.book_outlined,
              message: '开始记录每天的心情吧',
              actionLabel: '写日记',
              onAction: () => _openEdit(context),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
              children: [
                AppSurfaceCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppSectionHeader(
                        title: '记录概览',
                        subtitle: '累计、本月和连续写作状态',
                        padding: EdgeInsets.zero,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _stat(
                              context,
                              '累计',
                              '${provider.totalCount} 篇',
                              Icons.book_outlined,
                              cs.primary,
                            ),
                          ),
                          _metricDivider(cs),
                          Expanded(
                            child: _stat(
                              context,
                              '本月',
                              '${provider.thisMonthCount} 篇',
                              Icons.calendar_month,
                              Colors.green,
                            ),
                          ),
                          _metricDivider(cs),
                          Expanded(
                            child: _stat(
                              context,
                              '连续',
                              '${provider.currentStreak} 天',
                              Icons.bolt,
                              Colors.orange,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      MoodHeatmap(entriesByDate: provider.entriesByDate),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                AppSectionHeader(
                  title: '最近日记',
                  subtitle: '${entries.length} 篇记录',
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                ),
                ...entries.map((entry) => _DiaryCard(entry: entry)),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEdit(context),
        icon: const Icon(Icons.edit_note),
        label: const Text('写日记'),
      ),
    );
  }

  Widget _stat(
    BuildContext context,
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, color: color, size: 17),
        ),
        const SizedBox(height: 10),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          title,
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurface.withValues(alpha: 0.62),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _metricDivider(ColorScheme cs) {
    return Container(
      width: 1,
      height: 42,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      color: cs.outlineVariant.withValues(alpha: 0.55),
    );
  }

  void _openEdit(BuildContext context, {DiaryEntry? entry, DateTime? date}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DiaryEditScreen(entry: entry, initialDate: date),
      ),
    );
  }

  void _showMoodStats(BuildContext context, DiaryProvider p) {
    final dist = p.moodDistribution(days: 30);
    final total = dist.values.fold(0, (s, v) => s + v);
    showAppModalSheet(
      context: context,
      builder: (_) => AppModalSheet(
        title: '近 30 天心情分布',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (total == 0)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('暂无数据')),
              )
            else
              ...Mood.values.map((m) {
                final c = dist[m] ?? 0;
                final pct = total == 0 ? 0.0 : c / total;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 52,
                        child: Text(
                          '${m.emoji} ${m.label}',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: pct,
                            minHeight: 10,
                            backgroundColor: Colors.grey.shade200,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 40,
                        child: Text(
                          '$c 篇',
                          textAlign: TextAlign.end,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _DiaryCard extends StatelessWidget {
  final DiaryEntry entry;
  const _DiaryCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final lunar = LunarCalendar.fromSolar(entry.date);
    final accent = _moodColor(entry.mood, cs);

    return AppSurfaceCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => DiaryEditScreen(entry: entry)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6,
            height: 98,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${entry.date.month}/${entry.date.day}',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: accent,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            lunar.dayChineseText,
                            style: TextStyle(
                              fontSize: 10,
                              color: accent.withValues(alpha: 0.82),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (entry.mood != null)
                                _DiaryBadge(
                                  label: entry.mood!.emoji,
                                  color: accent,
                                ),
                              if (entry.weather != null) ...[
                                const SizedBox(width: 6),
                                _DiaryBadge(
                                  label: entry.weather!.emoji,
                                  color: cs.primary,
                                ),
                              ],
                              const Spacer(),
                              Text(
                                '${entry.updatedAt.hour.toString().padLeft(2, '0')}:${entry.updatedAt.minute.toString().padLeft(2, '0')}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: cs.onSurface.withValues(alpha: 0.5),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            entry.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (entry.preview.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    entry.preview,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.72),
                      height: 1.55,
                    ),
                  ),
                ],
                if (entry.tags.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: entry.tags
                        .map(
                          (t) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest.withValues(
                                alpha: 0.75,
                              ),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '#$t',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurface.withValues(alpha: 0.7),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DiaryBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _DiaryBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: cs.onSurface.withValues(alpha: 0.68),
        ),
      ),
    );
  }
}

Color _moodColor(Mood? mood, ColorScheme cs) {
  switch (mood) {
    case Mood.awesome:
      return const Color(0xFF43A047);
    case Mood.good:
      return cs.primary;
    case Mood.okay:
      return const Color(0xFF78909C);
    case Mood.bad:
      return const Color(0xFFFB8C00);
    case Mood.terrible:
      return cs.error;
    case null:
      return cs.primary;
  }
}

class DiaryEditScreen extends StatefulWidget {
  final DiaryEntry? entry;
  final DateTime? initialDate;
  const DiaryEditScreen({super.key, this.entry, this.initialDate});

  @override
  State<DiaryEditScreen> createState() => _DiaryEditScreenState();
}

class _DiaryEditScreenState extends State<DiaryEditScreen> {
  late TextEditingController _content;
  late TextEditingController _tag;
  late DateTime _date;
  Mood? _mood;
  Weather? _weather;
  List<String> _tags = [];

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _content = TextEditingController(text: e?.content ?? '');
    _tag = TextEditingController();
    _date = e?.date ?? widget.initialDate ?? DateTime.now();
    _mood = e?.mood;
    _weather = e?.weather;
    _tags = [...?e?.tags];
  }

  @override
  void dispose() {
    _content.dispose();
    _tag.dispose();
    super.dispose();
  }

  void _save() {
    final text = _content.text.trim();
    final provider = context.read<DiaryProvider>();

    if (text.isEmpty && _mood == null && _weather == null && _tags.isEmpty) {
      if (widget.entry != null) provider.delete(widget.entry!.id);
      Navigator.pop(context);
      return;
    }

    final entry = DiaryEntry(
      id: widget.entry?.id,
      date: _date,
      content: text,
      mood: _mood,
      weather: _weather,
      tags: _tags,
      imagePaths: widget.entry?.imagePaths ?? const [],
      location: widget.entry?.location,
      createdAt: widget.entry?.createdAt,
    );
    provider.addOrUpdate(entry);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final lunar = LunarCalendar.fromSolar(_date);
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('日记'),
        actions: [IconButton(icon: const Icon(Icons.check), onPressed: _save)],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 日期/农历
          GestureDetector(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(2000),
                lastDate: DateTime(2099, 12, 31),
              );
              if (picked != null) setState(() => _date = picked);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_today, size: 16, color: cs.primary),
                  const SizedBox(width: 8),
                  Text(
                    '${_date.year}年${_date.month}月${_date.day}日',
                    style: TextStyle(
                      color: cs.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    lunar.chineseText,
                    style: TextStyle(
                      color: cs.primary.withValues(alpha: 0.7),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // 心情
          const Text(
            '今天心情如何？',
            style: TextStyle(fontSize: 13, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: Mood.values.map((m) {
              final selected = _mood == m;
              return GestureDetector(
                onTap: () => setState(() => _mood = selected ? null : m),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: selected
                        ? cs.primary.withValues(alpha: 0.15)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selected ? cs.primary : Colors.grey.shade300,
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(m.emoji, style: const TextStyle(fontSize: 24)),
                      const SizedBox(height: 2),
                      Text(m.label, style: const TextStyle(fontSize: 11)),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          // 天气
          const Text('天气', style: TextStyle(fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: Weather.values.map((w) {
              final selected = _weather == w;
              return FilterChip(
                label: Text('${w.emoji} ${w.label}'),
                selected: selected,
                onSelected: (_) =>
                    setState(() => _weather = selected ? null : w),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          // 标签
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _tag,
                  decoration: const InputDecoration(
                    hintText: '添加标签 (如: 学习、旅行)',
                    prefixIcon: Icon(Icons.tag),
                  ),
                  onSubmitted: (v) {
                    if (v.trim().isNotEmpty) {
                      setState(() {
                        _tags.add(v.trim());
                        _tag.clear();
                      });
                    }
                  },
                ),
              ),
            ],
          ),
          if (_tags.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: _tags
                  .map(
                    (t) => Chip(
                      label: Text(t),
                      onDeleted: () => setState(() => _tags.remove(t)),
                    ),
                  )
                  .toList(),
            ),
          ],
          const SizedBox(height: 16),
          // 正文
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: TextField(
              controller: _content,
              maxLines: 12,
              minLines: 8,
              decoration: const InputDecoration(
                hintText: '写下今天的故事...',
                border: InputBorder.none,
                focusedBorder: InputBorder.none,
                enabledBorder: InputBorder.none,
              ),
              style: const TextStyle(fontSize: 15, height: 1.6),
            ),
          ),
        ],
      ),
    );
  }
}
