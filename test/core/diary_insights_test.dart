import 'package:test/test.dart';

import 'package:duoyi/core/diary_insights.dart';
import 'package:duoyi/models/diary_entry.dart';

void main() {
  test('buildInsights summarizes mood trend, themes and streak', () {
    final today = DateTime(2026, 5, 20);
    final entries = <DiaryEntry>[
      _entry(today, Mood.good, ['工作'], '工作推进顺利，晚上散步放松。'),
      _entry(today.subtract(const Duration(days: 1)), Mood.awesome, [
        '工作',
      ], '工作会议有结果，状态不错。'),
      _entry(today.subtract(const Duration(days: 2)), Mood.good, [
        '运动',
      ], '运动之后睡眠更好。'),
      _entry(today.subtract(const Duration(days: 16)), Mood.bad, [
        '压力',
      ], '工作压力比较明显。'),
      _entry(today.subtract(const Duration(days: 17)), Mood.terrible, [
        '压力',
      ], '压力很大，睡眠也不好。'),
    ];

    final insights = DiaryInsightEngine.buildInsights(
      entries,
      today: today,
      limit: 5,
    );

    expect(insights.first.kind, DiaryInsightKind.overview);
    expect(insights.first.title, contains('开心'));
    expect(
      insights.any(
        (insight) =>
            insight.kind == DiaryInsightKind.emotionTrend &&
            insight.title == '情绪正在回升',
      ),
      isTrue,
    );
    expect(
      insights.any(
        (insight) =>
            insight.kind == DiaryInsightKind.theme &&
            insight.message.contains('#工作'),
      ),
      isTrue,
    );
    expect(
      insights.any((insight) => insight.kind == DiaryInsightKind.streak),
      isTrue,
    );
  });

  test('buildInsights warns when low mood entries dominate', () {
    final today = DateTime(2026, 5, 20);
    final insights = DiaryInsightEngine.buildInsights(
      [
        _entry(today, Mood.bad, const [], '疲惫'),
        _entry(
          today.subtract(const Duration(days: 1)),
          Mood.terrible,
          const [],
          '焦虑',
        ),
        _entry(
          today.subtract(const Duration(days: 2)),
          Mood.bad,
          const [],
          '压力',
        ),
        _entry(
          today.subtract(const Duration(days: 3)),
          Mood.okay,
          const [],
          '平静',
        ),
      ],
      today: today,
      limit: 5,
    );

    expect(
      insights.any((insight) => insight.kind == DiaryInsightKind.attention),
      isTrue,
    );
  });

  test('buildInsights returns empty list without recent entries', () {
    final today = DateTime(2026, 5, 20);
    final oldEntry = _entry(
      today.subtract(const Duration(days: 45)),
      Mood.good,
      const [],
      '很久以前',
    );

    expect(DiaryInsightEngine.buildInsights([oldEntry], today: today), isEmpty);
  });

  test('buildInsights preserves kinds, scores, order, and raw tags across zh and en', () {
    final today = DateTime(2026, 5, 20);
    final entries = <DiaryEntry>[
      _entry(today, Mood.good, ['工作', '生活'], '工作推进顺利，晚上散步放松。'),
      _entry(today.subtract(const Duration(days: 1)), Mood.awesome, [
        '工作',
      ], '工作会议有结果，状态不错。'),
      _entry(today.subtract(const Duration(days: 2)), Mood.good, [
        '运动',
      ], '运动之后睡眠更好。'),
      _entry(today.subtract(const Duration(days: 16)), Mood.bad, [
        '压力',
      ], '工作压力比较明显。'),
      _entry(today.subtract(const Duration(days: 17)), Mood.terrible, [
        '压力',
      ], '压力很大，睡眠也不好。'),
    ];

    final defaultZh = DiaryInsightEngine.buildInsights(
      entries,
      today: today,
      limit: 5,
    );
    final explicitZh = DiaryInsightEngine.buildInsights(
      entries,
      today: today,
      limit: 5,
      locale: 'zh',
    );
    final explicitEn = DiaryInsightEngine.buildInsights(
      entries,
      today: today,
      limit: 5,
      locale: 'en',
    );

    expect(explicitZh.length, defaultZh.length);
    expect(explicitEn.length, defaultZh.length);

    for (var i = 0; i < defaultZh.length; i++) {
      expect(explicitZh[i].kind, defaultZh[i].kind);
      expect(explicitZh[i].score, defaultZh[i].score);
      expect(explicitZh[i].title, defaultZh[i].title);
      expect(explicitZh[i].message, defaultZh[i].message);

      expect(explicitEn[i].kind, defaultZh[i].kind);
      expect(explicitEn[i].score, defaultZh[i].score);
    }

    // Overview branch
    expect(explicitZh[0].kind, DiaryInsightKind.overview);
    expect(explicitZh[0].title, '近期心情以开心为主');
    expect(explicitZh[0].message, '近 30 天记录 5 篇，其中 5 篇带有心情。');
    expect(explicitEn[0].kind, DiaryInsightKind.overview);
    expect(explicitEn[0].title, 'Recent mood is mostly Good');
    expect(
      explicitEn[0].message,
      'Recorded 5 entries in the past 30 days, including 5 entries with mood.',
    );

    // Emotion trend branch (rising)
    expect(explicitZh[1].kind, DiaryInsightKind.emotionTrend);
    expect(explicitZh[1].title, '情绪正在回升');
    expect(
      explicitZh[1].message,
      '最近半月平均心情比前半月更积极，可以留意哪些安排带来了改善。',
    );
    expect(explicitEn[1].kind, DiaryInsightKind.emotionTrend);
    expect(explicitEn[1].title, 'Mood is improving');
    expect(
      explicitEn[1].message,
      'Average mood in the past half month is more positive than the earlier half. Notice what arrangements brought improvement.',
    );

    // Theme branch (tags with preserved raw tags)
    expect(explicitZh[2].kind, DiaryInsightKind.theme);
    expect(explicitZh[2].title, '近期主题集中');
    expect(explicitZh[2].message, '出现最多的主题是 #压力、#工作、#生活，可作为本月复盘线索。');
    expect(explicitEn[2].kind, DiaryInsightKind.theme);
    expect(explicitEn[2].title, 'Recent themes are focused');
    expect(
      explicitEn[2].message,
      'The most frequent themes are #压力, #工作, #生活, which can serve as review clues this month.',
    );

    // Streak branch
    expect(explicitZh[3].kind, DiaryInsightKind.streak);
    expect(explicitZh[3].title, '记录连续性不错');
    expect(explicitZh[3].message, '已连续记录 3 天，适合在每天固定时段做简短复盘。');
    expect(explicitEn[3].kind, DiaryInsightKind.streak);
    expect(explicitEn[3].title, 'Consistent writing streak');
    expect(
      explicitEn[3].message,
      'Recorded for 3 consecutive days, ideal for a brief review at a regular time each day.',
    );
  });

  test('buildInsights exercises steady and dipping emotion trends in both locales', () {
    final today = DateTime(2026, 6, 1);

    // Steady delta (< 0.35)
    final steadyEntries = <DiaryEntry>[
      _entry(today, Mood.good, const [], '今天不错'),
      _entry(today.subtract(const Duration(days: 20)), Mood.good, const [], '那天不错'),
    ];
    final steadyZh = DiaryInsightEngine.buildInsights(
      steadyEntries,
      today: today,
      locale: 'zh',
    );
    final steadyEn = DiaryInsightEngine.buildInsights(
      steadyEntries,
      today: today,
      locale: 'en',
    );
    final trendZhSteady = steadyZh.firstWhere((i) => i.kind == DiaryInsightKind.emotionTrend);
    final trendEnSteady = steadyEn.firstWhere((i) => i.kind == DiaryInsightKind.emotionTrend);
    expect(trendZhSteady.title, '情绪走势平稳');
    expect(trendZhSteady.message, '最近半月平均心情与前半月接近，记录节奏比较稳定。');
    expect(trendEnSteady.title, 'Mood trend is steady');
    expect(
      trendEnSteady.message,
      'Average mood in the past half month is close to the earlier half, and your recording pace is steady.',
    );
    expect(trendEnSteady.score, trendZhSteady.score);

    // Dipping delta (< 0)
    final dippingEntries = <DiaryEntry>[
      _entry(today, Mood.bad, const [], '近期压力大'),
      _entry(today.subtract(const Duration(days: 20)), Mood.awesome, const [], '之前很开心'),
    ];
    final dippingZh = DiaryInsightEngine.buildInsights(
      dippingEntries,
      today: today,
      locale: 'zh',
    );
    final dippingEn = DiaryInsightEngine.buildInsights(
      dippingEntries,
      today: today,
      locale: 'en',
    );
    final trendZhDipping = dippingZh.firstWhere((i) => i.kind == DiaryInsightKind.emotionTrend);
    final trendEnDipping = dippingEn.firstWhere((i) => i.kind == DiaryInsightKind.emotionTrend);
    expect(trendZhDipping.title, '情绪有走低迹象');
    expect(trendZhDipping.message, '最近半月平均心情低于前半月，建议减少高压安排并记录触发原因。');
    expect(trendEnDipping.title, 'Mood is dipping');
    expect(
      trendEnDipping.message,
      'Average mood in the past half month is lower than the earlier half. Consider reducing high-stress plans and noting triggers.',
    );
    expect(trendEnDipping.score, trendZhDipping.score);
  });

  test('buildInsights exercises theme from keywords when tags are empty in both locales', () {
    final today = DateTime(2026, 7, 10);
    final entries = <DiaryEntry>[
      _entry(today, Mood.good, const [], '复盘 深度专注，复盘 带来启发。'),
      _entry(today.subtract(const Duration(days: 1)), Mood.good, const [], '复盘 总结与练习。'),
    ];

    final zh = DiaryInsightEngine.buildInsights(entries, today: today, locale: 'zh');
    final en = DiaryInsightEngine.buildInsights(entries, today: today, locale: 'en');

    final themeZh = zh.firstWhere((i) => i.kind == DiaryInsightKind.theme);
    final themeEn = en.firstWhere((i) => i.kind == DiaryInsightKind.theme);

    expect(themeZh.title, '近期内容线索');
    expect(themeZh.message, contains('日记中反复出现'));
    expect(themeZh.message, contains('复盘'));
    expect(themeEn.title, 'Recent content clues');
    expect(themeEn.message, contains('Recurring in your diary:'));
    expect(themeEn.message, contains('复盘'));
    expect(themeEn.score, themeZh.score);
  });

  test('buildInsights exercises single tag singular phrasing and singular counts in en', () {
    final today = DateTime(2026, 8, 1);
    final entries = <DiaryEntry>[
      _entry(today, Mood.awesome, ['独奏'], '今天写了一首曲子。'),
    ];

    final zh = DiaryInsightEngine.buildInsights(
      entries,
      today: today,
      days: 1,
      locale: 'zh',
    );
    final en = DiaryInsightEngine.buildInsights(
      entries,
      today: today,
      days: 1,
      locale: 'en',
    );

    // Overview singular
    expect(zh[0].title, '近期心情以超棒为主');
    expect(zh[0].message, '近 1 天记录 1 篇，其中 1 篇带有心情。');
    expect(en[0].title, 'Recent mood is mostly Great');
    expect(en[0].message, 'Recorded 1 entry in the past 1 day, including 1 entry with mood.');

    // Theme singular
    expect(zh[1].title, '近期主题集中');
    expect(zh[1].message, '出现最多的主题是 #独奏，可作为本月复盘线索。');
    expect(en[1].title, 'Recent themes are focused');
    expect(
      en[1].message,
      'The most frequent theme is #独奏, which can serve as a review clue this month.',
    );
  });

  test('buildInsights exercises overview without mood and attention branch in both locales', () {
    final today = DateTime(2026, 9, 15);
    final noMoodEntries = <DiaryEntry>[
      _entry(today, null, const [], '只记录了文字，没有选心情。'),
    ];
    final noMoodZh = DiaryInsightEngine.buildInsights(
      noMoodEntries,
      today: today,
      days: 1,
      locale: 'zh',
    );
    final noMoodEn = DiaryInsightEngine.buildInsights(
      noMoodEntries,
      today: today,
      days: 1,
      locale: 'en',
    );
    expect(noMoodZh[0].title, '日记记录已开始');
    expect(noMoodZh[0].message, '近 1 天记录 1 篇，可继续补充心情来生成情绪走势。');
    expect(noMoodEn[0].title, 'Diary journaling has started');
    expect(
      noMoodEn[0].message,
      'Recorded 1 entry in the past 1 day, keep adding moods to generate emotional trends.',
    );

    // Attention branch (low moods >= 3 and ratio >= 0.35)
    final attentionEntries = <DiaryEntry>[
      _entry(today, Mood.bad, const [], '很疲惫'),
      _entry(today.subtract(const Duration(days: 1)), Mood.terrible, const [], '很不顺'),
      _entry(today.subtract(const Duration(days: 2)), Mood.bad, const [], '压力依然很大'),
      _entry(today.subtract(const Duration(days: 3)), Mood.okay, const [], '稍微平静'),
    ];
    final attentionZh = DiaryInsightEngine.buildInsights(
      attentionEntries,
      today: today,
      limit: 5,
      locale: 'zh',
    );
    final attentionEn = DiaryInsightEngine.buildInsights(
      attentionEntries,
      today: today,
      limit: 5,
      locale: 'en',
    );
    final attZh = attentionZh.firstWhere((i) => i.kind == DiaryInsightKind.attention);
    final attEn = attentionEn.firstWhere((i) => i.kind == DiaryInsightKind.attention);
    expect(attZh.title, '低落心情偏多');
    expect(attZh.message, '近期待关注心情占比 75%，可以标记原因并安排休息。');
    expect(attEn.title, 'Low moods are frequent');
    expect(
      attEn.message,
      'Moods needing attention make up 75% recently. Consider noting causes and planning some rest.',
    );
    expect(attEn.score, attZh.score);
  });

  test('buildInsights renders all 5 mood labels correctly across locales', () {
    final today = DateTime(2026, 10, 1);
    final moodCases = <Mood, (String, String)>{
      Mood.awesome: ('超棒', 'Great'),
      Mood.good: ('开心', 'Good'),
      Mood.okay: ('平静', 'Calm'),
      Mood.bad: ('郁闷', 'Low'),
      Mood.terrible: ('糟糕', 'Terrible'),
    };

    for (final entry in moodCases.entries) {
      final mood = entry.key;
      final (zhLabel, enLabel) = entry.value;
      final entries = [_entry(today, mood, const [], '测试心情')];

      final zh = DiaryInsightEngine.buildInsights(entries, today: today, locale: 'zh');
      final en = DiaryInsightEngine.buildInsights(entries, today: today, locale: 'en');

      expect(zh.first.title, '近期心情以$zhLabel为主');
      expect(en.first.title, 'Recent mood is mostly $enLabel');
    }
  });
}

DiaryEntry _entry(DateTime date, Mood? mood, List<String> tags, String content) {
  return DiaryEntry(date: date, mood: mood, tags: tags, content: content);
}
