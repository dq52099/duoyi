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
}

DiaryEntry _entry(DateTime date, Mood mood, List<String> tags, String content) {
  return DiaryEntry(date: date, mood: mood, tags: tags, content: content);
}
