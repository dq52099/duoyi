import '../models/diary_entry.dart';

class DiaryDeepReviewPrompt {
  final String systemPrompt;
  final String userPrompt;
  final String summary;

  const DiaryDeepReviewPrompt({
    required this.systemPrompt,
    required this.userPrompt,
    required this.summary,
  });
}

class DiaryDeepReviewBuilder {
  const DiaryDeepReviewBuilder._();

  static DiaryDeepReviewPrompt build({
    required Iterable<DiaryEntry> entries,
    DateTime? today,
    int days = 30,
    int maxEntries = 18,
  }) {
    final now = _dateOnly(today ?? DateTime.now());
    final cutoff = now.subtract(Duration(days: days - 1));
    final recent =
        entries
            .where((entry) => !_dateOnly(entry.date).isBefore(cutoff))
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));
    final selected = recent.take(maxEntries).toList(growable: false);
    final moodCounts = <String, int>{};
    final tagCounts = <String, int>{};
    for (final entry in recent) {
      final mood = entry.mood?.label;
      if (mood != null) moodCounts[mood] = (moodCounts[mood] ?? 0) + 1;
      for (final tag in entry.tags) {
        final clean = tag.trim();
        if (clean.isEmpty) continue;
        tagCounts[clean] = (tagCounts[clean] ?? 0) + 1;
      }
    }
    final topMoods = _topLabels(moodCounts, 3);
    final topTags = _topLabels(tagCounts, 5);
    final summary =
        '近 $days 天日记 ${recent.length} 篇；心情：${topMoods.isEmpty ? '未记录' : topMoods.join('、')}；'
        '主题：${topTags.isEmpty ? '未标记' : topTags.map((tag) => '#$tag').join('、')}。';
    final diaryLines = selected
        .map((entry) {
          final meta = [
            _dateLabel(entry.date),
            if (entry.mood != null) '心情=${entry.mood!.label}',
            if (entry.weather != null) '天气=${entry.weather!.label}',
            if (entry.tags.isNotEmpty) '标签=${entry.tags.join(',')}',
            if ((entry.location ?? '').trim().isNotEmpty)
              '地点=${entry.location!.trim()}',
          ].join('；');
          return '[$meta]\n${_truncate(entry.content.trim(), 360)}';
        })
        .join('\n\n');
    return DiaryDeepReviewPrompt(
      systemPrompt:
          '你是一个谨慎、温和、务实的日记复盘助手。你只能基于用户给出的日记内容分析，'
          '不要做医学诊断，不要夸大结论。请输出结构化中文复盘，包含：'
          '1. 近期主线；2. 情绪与能量变化；3. 反复出现的触发因素；'
          '4. 值得保留的做法；5. 接下来 7 天的 3 条具体行动。控制在 500-900 字。',
      userPrompt: '$summary\n\n以下是最近日记摘录，按时间倒序排列：\n\n$diaryLines',
      summary: summary,
    );
  }

  static List<String> _topLabels(Map<String, int> counts, int limit) {
    final entries = counts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });
    return entries
        .take(limit)
        .map((entry) => '${entry.key} ${entry.value}')
        .toList();
  }

  static DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  static String _dateLabel(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  static String _truncate(String value, int maxLength) {
    if (value.length <= maxLength) return value;
    return '${value.substring(0, maxLength)}...';
  }
}
