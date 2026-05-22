import 'package:test/test.dart';

import 'package:duoyi/core/diary_deep_review.dart';
import 'package:duoyi/models/diary_entry.dart';

void main() {
  test(
    'DiaryDeepReviewBuilder builds structured prompt from recent diary data',
    () {
      final today = DateTime(2026, 5, 20);
      final prompt = DiaryDeepReviewBuilder.build(
        today: today,
        entries: [
          DiaryEntry(
            date: today,
            mood: Mood.good,
            weather: Weather.sunny,
            tags: const ['工作', '散步'],
            location: '上海',
            content: '今天推进了重要项目，晚上散步后状态更稳定。',
          ),
          DiaryEntry(
            date: today.subtract(const Duration(days: 1)),
            mood: Mood.bad,
            tags: const ['压力'],
            content: '会议很多，有些疲惫，但晚上做了短复盘。',
          ),
          DiaryEntry(
            date: today.subtract(const Duration(days: 45)),
            mood: Mood.awesome,
            tags: const ['旧记录'],
            content: '很久以前的内容不应该进入近 30 天复盘。',
          ),
        ],
      );

      expect(prompt.systemPrompt, contains('日记复盘助手'));
      expect(prompt.systemPrompt, contains('接下来 7 天的 3 条具体行动'));
      expect(prompt.summary, contains('近 30 天日记 2 篇'));
      expect(prompt.summary, contains('开心 1'));
      expect(prompt.summary, contains('#工作'));
      expect(prompt.userPrompt, contains('[2026-05-20'));
      expect(prompt.userPrompt, contains('心情=开心'));
      expect(prompt.userPrompt, contains('天气=晴'));
      expect(prompt.userPrompt, contains('地点=上海'));
      expect(prompt.userPrompt, contains('今天推进了重要项目'));
      expect(prompt.userPrompt, isNot(contains('很久以前的内容')));
    },
  );
}
