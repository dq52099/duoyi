import '../models/diary_entry.dart';

enum DiaryInsightLocale {
  zh,
  en;

  static DiaryInsightLocale resolve(Object? locale) {
    if (locale == null) return DiaryInsightLocale.zh;
    if (locale is DiaryInsightLocale) return locale;
    final raw = switch (locale) {
      String s => s,
      _ => locale.toString(),
    }.trim().toLowerCase();
    final token = raw.split(RegExp(r'[^a-z]')).firstWhere(
      (part) => part == 'en' || part == 'zh',
      orElse: () => '',
    );
    if (token == 'en' || raw.endsWith('.en') || raw.startsWith('en')) {
      return DiaryInsightLocale.en;
    }
    return DiaryInsightLocale.zh;
  }
}

/// Pure Dart copy helper for Diary Insights.
class DiaryInsightCopy {
  final DiaryInsightLocale locale;

  const DiaryInsightCopy([this.locale = DiaryInsightLocale.zh]);

  factory DiaryInsightCopy.from(Object? locale) =>
      DiaryInsightCopy(DiaryInsightLocale.resolve(locale));

  bool get isEn => locale == DiaryInsightLocale.en;

  String moodLabel(Mood mood) {
    if (isEn) {
      return switch (mood) {
        Mood.awesome => 'Great',
        Mood.good => 'Good',
        Mood.okay => 'Calm',
        Mood.bad => 'Low',
        Mood.terrible => 'Terrible',
      };
    }
    return switch (mood) {
      Mood.awesome => '超棒',
      Mood.good => '开心',
      Mood.okay => '平静',
      Mood.bad => '郁闷',
      Mood.terrible => '糟糕',
    };
  }

  // 1. Overview
  String overviewTitle(Mood? dominantMood) {
    if (dominantMood == null) {
      return isEn ? 'Diary journaling has started' : '日记记录已开始';
    }
    final label = moodLabel(dominantMood);
    return isEn ? 'Recent mood is mostly $label' : '近期心情以$label为主';
  }

  String overviewMessage({
    required int days,
    required int entryCount,
    int? moodCount,
  }) {
    if (moodCount == null) {
      if (isEn) {
        final dayStr = days == 1 ? '1 day' : '$days days';
        final entryStr = entryCount == 1 ? '1 entry' : '$entryCount entries';
        return 'Recorded $entryStr in the past $dayStr, keep adding moods to generate emotional trends.';
      }
      return '近 $days 天记录 $entryCount 篇，可继续补充心情来生成情绪走势。';
    }
    if (isEn) {
      final dayStr = days == 1 ? '1 day' : '$days days';
      final entryStr = entryCount == 1 ? '1 entry' : '$entryCount entries';
      final moodStr = moodCount == 1 ? '1 entry' : '$moodCount entries';
      return 'Recorded $entryStr in the past $dayStr, including $moodStr with mood.';
    }
    return '近 $days 天记录 $entryCount 篇，其中 $moodCount 篇带有心情。';
  }

  // 2. Emotion Trend
  String emotionTrendTitle(int trendKind) {
    // 0: steady, 1: rising, -1: dipping
    if (isEn) {
      return switch (trendKind) {
        1 => 'Mood is improving',
        -1 => 'Mood is dipping',
        _ => 'Mood trend is steady',
      };
    }
    return switch (trendKind) {
      1 => '情绪正在回升',
      -1 => '情绪有走低迹象',
      _ => '情绪走势平稳',
    };
  }

  String emotionTrendMessage(int trendKind) {
    if (isEn) {
      return switch (trendKind) {
        1 =>
          'Average mood in the past half month is more positive than the earlier half. Notice what arrangements brought improvement.',
        -1 =>
          'Average mood in the past half month is lower than the earlier half. Consider reducing high-stress plans and noting triggers.',
        _ =>
          'Average mood in the past half month is close to the earlier half, and your recording pace is steady.',
      };
    }
    return switch (trendKind) {
      1 => '最近半月平均心情比前半月更积极，可以留意哪些安排带来了改善。',
      -1 => '最近半月平均心情低于前半月，建议减少高压安排并记录触发原因。',
      _ => '最近半月平均心情与前半月接近，记录节奏比较稳定。',
    };
  }

  // 3. Theme
  String themeTagsTitle() => isEn ? 'Recent themes are focused' : '近期主题集中';

  String themeTagsMessage(List<String> tags) {
    final separator = isEn ? ', ' : '、';
    final labels = tags.map((t) => '#$t').join(separator);
    if (isEn) {
      final subject = tags.length == 1 ? 'theme is' : 'themes are';
      final noun = tags.length == 1 ? 'a review clue' : 'review clues';
      return 'The most frequent $subject $labels, which can serve as $noun this month.';
    }
    return '出现最多的主题是 $labels，可作为本月复盘线索。';
  }

  String themeKeywordsTitle() => isEn ? 'Recent content clues' : '近期内容线索';

  String themeKeywordsMessage(List<String> keywords) {
    final separator = isEn ? ', ' : '、';
    final clues = keywords.join(separator);
    if (isEn) {
      return 'Recurring in your diary: $clues, worth observing further.';
    }
    return '日记中反复出现 $clues，适合继续观察。';
  }

  // 4. Streak
  String streakTitle() => isEn ? 'Consistent writing streak' : '记录连续性不错';

  String streakMessage(int streak) {
    if (isEn) {
      final dayStr = streak == 1 ? '1 consecutive day' : '$streak consecutive days';
      return 'Recorded for $dayStr, ideal for a brief review at a regular time each day.';
    }
    return '已连续记录 $streak 天，适合在每天固定时段做简短复盘。';
  }

  // 5. Attention
  String attentionTitle() => isEn ? 'Low moods are frequent' : '低落心情偏多';

  String attentionMessage(int percent) {
    if (isEn) {
      return 'Moods needing attention make up $percent% recently. Consider noting causes and planning some rest.';
    }
    return '近期待关注心情占比 $percent%，可以标记原因并安排休息。';
  }
}
