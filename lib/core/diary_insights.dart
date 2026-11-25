import 'dart:collection';

import '../models/diary_entry.dart';
import 'diary_insight_copy.dart';

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

  static const int _maxCacheEntries = 16;
  static final LinkedHashMap<Object, List<DiaryInsight>> _cache =
      LinkedHashMap<Object, List<DiaryInsight>>();

  static List<DiaryInsight> buildInsights(
    Iterable<DiaryEntry> entries, {
    DateTime? today,
    int days = 30,
    int limit = 4,
    Object? locale = 'zh',
  }) {
    final now = _dateOnly(today ?? DateTime.now());
    final resolvedLocale = DiaryInsightLocale.resolve(locale);
    final fingerprint = _entriesFingerprint(entries);
    final cacheKey = (
      now.year,
      now.month,
      now.day,
      days,
      limit,
      resolvedLocale,
      fingerprint.$1,
      fingerprint.$2,
      fingerprint.$3,
    );
    final cached = _cache.remove(cacheKey);
    if (cached != null) {
      _cache[cacheKey] = cached;
      return cached;
    }

    final cutoff = now.subtract(Duration(days: days - 1));
    final recent =
        entries
            .where((entry) => !_dateOnly(entry.date).isBefore(cutoff))
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));
    if (recent.isEmpty) {
      const empty = <DiaryInsight>[];
      _putCache(cacheKey, empty);
      return empty;
    }

    final copy = DiaryInsightCopy(resolvedLocale);
    final insights = <DiaryInsight>[_overviewInsight(recent, days, copy)];
    final trend = _emotionTrendInsight(recent, now, days, copy);
    if (trend != null) insights.add(trend);
    final theme = _themeInsight(recent, copy);
    if (theme != null) insights.add(theme);
    final streak = _streakInsight(recent, now, copy);
    if (streak != null) insights.add(streak);
    final attention = _attentionInsight(recent, copy);
    if (attention != null) insights.add(attention);

    final result = List<DiaryInsight>.unmodifiable(insights.take(limit));
    _putCache(cacheKey, result);
    return result;
  }

  static void _putCache(Object key, List<DiaryInsight> value) {
    if (_cache.length >= _maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = value;
  }

  static (int, int, int) _entriesFingerprint(Iterable<DiaryEntry> entries) {
    var count = 0;
    var hashA = 0x811c9dc5;
    var hashB = 0;
    for (final entry in entries) {
      count++;
      var tagsHash = 0;
      for (final tag in entry.tags) {
        tagsHash = Object.hash(tagsHash, tag);
      }
      final itemHash = Object.hash(
        entry.id,
        entry.date.year,
        entry.date.month,
        entry.date.day,
        entry.updatedAt.millisecondsSinceEpoch,
        entry.mood?.index ?? -1,
        entry.weather?.index ?? -1,
        entry.content.hashCode,
        entry.tags.length,
        tagsHash,
      );
      hashA = Object.hash(hashA, itemHash);
      hashB = ((hashB * 31) ^ itemHash ^ (count * 0x9e3779b9)) & 0x3fffffff;
    }
    return (count, hashA, hashB);
  }

  static DiaryInsight _overviewInsight(
    List<DiaryEntry> entries,
    int days,
    DiaryInsightCopy copy,
  ) {
    final moodEntries = entries.where((entry) => entry.mood != null).toList();
    final dominantMood = _dominantMood(moodEntries);
    final title = copy.overviewTitle(dominantMood);
    final message = dominantMood == null
        ? copy.overviewMessage(days: days, entryCount: entries.length)
        : copy.overviewMessage(
            days: days,
            entryCount: entries.length,
            moodCount: moodEntries.length,
          );
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
    DiaryInsightCopy copy,
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
        title: copy.emotionTrendTitle(0),
        message: copy.emotionTrendMessage(0),
        score: delta.abs(),
      );
    }
    if (delta > 0) {
      return DiaryInsight(
        kind: DiaryInsightKind.emotionTrend,
        title: copy.emotionTrendTitle(1),
        message: copy.emotionTrendMessage(1),
        score: delta,
      );
    }
    return DiaryInsight(
      kind: DiaryInsightKind.emotionTrend,
      title: copy.emotionTrendTitle(-1),
      message: copy.emotionTrendMessage(-1),
      score: delta.abs(),
    );
  }

  static DiaryInsight? _themeInsight(
    List<DiaryEntry> entries,
    DiaryInsightCopy copy,
  ) {
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
      final tags =
          topTags.take(3).map((entry) => entry.key).toList(growable: false);
      return DiaryInsight(
        kind: DiaryInsightKind.theme,
        title: copy.themeTagsTitle(),
        message: copy.themeTagsMessage(tags),
        score: topTags.first.value.toDouble(),
      );
    }

    final keywords = _extractKeywords(entries);
    if (keywords.isEmpty) return null;
    return DiaryInsight(
      kind: DiaryInsightKind.theme,
      title: copy.themeKeywordsTitle(),
      message: copy.themeKeywordsMessage(
        keywords.take(3).toList(growable: false),
      ),
      score: keywords.length.toDouble(),
    );
  }

  static DiaryInsight? _streakInsight(
    List<DiaryEntry> entries,
    DateTime today,
    DiaryInsightCopy copy,
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
      title: copy.streakTitle(),
      message: copy.streakMessage(streak),
      score: streak.toDouble(),
    );
  }

  static DiaryInsight? _attentionInsight(
    List<DiaryEntry> entries,
    DiaryInsightCopy copy,
  ) {
    final lowMoodEntries = entries
        .where((entry) => entry.mood == Mood.bad || entry.mood == Mood.terrible)
        .toList();
    if (lowMoodEntries.length < 3) return null;
    final ratio = lowMoodEntries.length / entries.length;
    if (ratio < 0.35) return null;
    return DiaryInsight(
      kind: DiaryInsightKind.attention,
      title: copy.attentionTitle(),
      message: copy.attentionMessage((ratio * 100).round()),
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
