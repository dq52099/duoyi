import '../models/diary_entry.dart';

enum DiaryInsightKind { overview, emotionTrend, theme, streak, attention }

class DiaryInsight {
  final DiaryInsightKind kind;
  final String title;
  final String message;
  final double score;

  const DiaryInsight({
    required this.kind,
    required this.title,
    required this.message,
    this.score = 0,
  });
}

class DiaryInsightEngine {
  const DiaryInsightEngine._();

  static List<DiaryInsight> buildInsights(
    Iterable<DiaryEntry> entries, {
    DateTime? today,
    int days = 30,
    int limit = 4,
  }) {
    final now = _dateOnly(today ?? DateTime.now());
    final cutoff = now.subtract(Duration(days: days - 1));
    final recent =
        entries
            .where((entry) => !_dateOnly(entry.date).isBefore(cutoff))
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));
    if (recent.isEmpty) return const <DiaryInsight>[];

    final insights = <DiaryInsight>[_overviewInsight(recent, days)];
    final trend = _emotionTrendInsight(recent, now, days);
    if (trend != null) insights.add(trend);
    final theme = _themeInsight(recent);
    if (theme != null) insights.add(theme);
    final streak = _streakInsight(recent, now);
    if (streak != null) insights.add(streak);
    final attention = _attentionInsight(recent);
    if (attention != null) insights.add(attention);

    return insights.take(limit).toList(growable: false);
  }

  static DiaryInsight _overviewInsight(List<DiaryEntry> entries, int days) {
    final moodEntries = entries.where((entry) => entry.mood != null).toList();
    final dominantMood = _dominantMood(moodEntries);
    final title = dominantMood == null
        ? '日记记录已开始'
        : '近期心情以${dominantMood.label}为主';
    final message = dominantMood == null
        ? '近 $days 天记录 ${entries.length} 篇，可继续补充心情来生成情绪走势。'
        : '近 $days 天记录 ${entries.length} 篇，其中 ${moodEntries.length} 篇带有心情。';
    return DiaryInsight(
      kind: DiaryInsightKind.overview,
      title: title,
      message: message,
      score: entries.length / days,
    );
  }

  static DiaryInsight? _emotionTrendInsight(
    List<DiaryEntry> entries,
    DateTime today,
    int days,
  ) {
    final midpoint = today.subtract(Duration(days: (days / 2).floor() - 1));
    final currentScores = <int>[];
    final previousScores = <int>[];
    for (final entry in entries) {
      final mood = entry.mood;
      if (mood == null) continue;
      final score = _moodScore(mood);
      if (_dateOnly(entry.date).isBefore(midpoint)) {
        previousScores.add(score);
      } else {
        currentScores.add(score);
      }
    }
    if (currentScores.isEmpty || previousScores.isEmpty) return null;

    final current = _average(currentScores);
    final previous = _average(previousScores);
    final delta = current - previous;
    if (delta.abs() < 0.35) {
      return DiaryInsight(
        kind: DiaryInsightKind.emotionTrend,
        title: '情绪走势平稳',
        message: '最近半月平均心情与前半月接近，记录节奏比较稳定。',
        score: delta.abs(),
      );
    }
    if (delta > 0) {
      return DiaryInsight(
        kind: DiaryInsightKind.emotionTrend,
        title: '情绪正在回升',
        message: '最近半月平均心情比前半月更积极，可以留意哪些安排带来了改善。',
        score: delta,
      );
    }
    return DiaryInsight(
      kind: DiaryInsightKind.emotionTrend,
      title: '情绪有走低迹象',
      message: '最近半月平均心情低于前半月，建议减少高压安排并记录触发原因。',
      score: delta.abs(),
    );
  }

  static DiaryInsight? _themeInsight(List<DiaryEntry> entries) {
    final tagCounts = <String, int>{};
    for (final entry in entries) {
      for (final tag in entry.tags) {
        final normalized = tag.trim();
        if (normalized.isEmpty) continue;
        tagCounts[normalized] = (tagCounts[normalized] ?? 0) + 1;
      }
    }
    final topTags = tagCounts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });
    if (topTags.isNotEmpty) {
      final labels = topTags.take(3).map((entry) => '#${entry.key}').join('、');
      return DiaryInsight(
        kind: DiaryInsightKind.theme,
        title: '近期主题集中',
        message: '出现最多的主题是 $labels，可作为本月复盘线索。',
        score: topTags.first.value.toDouble(),
      );
    }

    final keywords = _extractKeywords(entries);
    if (keywords.isEmpty) return null;
    return DiaryInsight(
      kind: DiaryInsightKind.theme,
      title: '近期内容线索',
      message: '日记中反复出现 ${keywords.take(3).join('、')}，适合继续观察。',
      score: keywords.length.toDouble(),
    );
  }

  static DiaryInsight? _streakInsight(
    List<DiaryEntry> entries,
    DateTime today,
  ) {
    final dates = entries.map((entry) => _dateOnly(entry.date)).toSet();
    var cursor = today;
    if (!dates.contains(cursor)) {
      cursor = today.subtract(const Duration(days: 1));
      if (!dates.contains(cursor)) return null;
    }
    var streak = 0;
    while (dates.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    if (streak < 3) return null;
    return DiaryInsight(
      kind: DiaryInsightKind.streak,
      title: '记录连续性不错',
      message: '已连续记录 $streak 天，适合在每天固定时段做简短复盘。',
      score: streak.toDouble(),
    );
  }

  static DiaryInsight? _attentionInsight(List<DiaryEntry> entries) {
    final lowMoodEntries = entries
        .where((entry) => entry.mood == Mood.bad || entry.mood == Mood.terrible)
        .toList();
    if (lowMoodEntries.length < 3) return null;
    final ratio = lowMoodEntries.length / entries.length;
    if (ratio < 0.35) return null;
    return DiaryInsight(
      kind: DiaryInsightKind.attention,
      title: '低落心情偏多',
      message: '近期待关注心情占比 ${(ratio * 100).round()}%，可以标记原因并安排休息。',
      score: ratio,
    );
  }

  static Mood? _dominantMood(List<DiaryEntry> entries) {
    final counts = <Mood, int>{};
    for (final entry in entries) {
      final mood = entry.mood;
      if (mood == null) continue;
      counts[mood] = (counts[mood] ?? 0) + 1;
    }
    if (counts.isEmpty) return null;
    final ranked = counts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0
            ? byCount
            : _moodScore(b.key).compareTo(_moodScore(a.key));
      });
    return ranked.first.key;
  }

  static List<String> _extractKeywords(List<DiaryEntry> entries) {
    final stopWords = {
      '今天',
      '感觉',
      '一个',
      '还是',
      '因为',
      '所以',
      '然后',
      '但是',
      '自己',
      '没有',
      '比较',
    };
    final counts = <String, int>{};
    final pattern = RegExp(r'[\u4e00-\u9fa5A-Za-z0-9]{2,}');
    for (final entry in entries) {
      for (final match in pattern.allMatches(entry.content)) {
        final word = match.group(0)!.trim();
        if (word.length < 2 || stopWords.contains(word)) continue;
        counts[word] = (counts[word] ?? 0) + 1;
      }
    }
    final ranked = counts.entries.where((entry) => entry.value >= 2).toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });
    return ranked.map((entry) => entry.key).toList(growable: false);
  }

  static int _moodScore(Mood mood) => switch (mood) {
    Mood.awesome => 5,
    Mood.good => 4,
    Mood.okay => 3,
    Mood.bad => 2,
    Mood.terrible => 1,
  };

  static double _average(List<int> values) =>
      values.fold<int>(0, (sum, value) => sum + value) / values.length;

  static DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);
}
