import 'dart:convert';

import 'package:test/test.dart';

import 'package:duoyi/core/diary_deep_review.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/diary_entry.dart';

void main() {
  late AppLocale savedLocale;

  setUp(() => savedLocale = I18n.current);
  tearDown(() => I18n.setLocale(savedLocale));

  test(
    'DiaryDeepReviewBuilder builds structured prompt from recent diary data',
    () {
      final today = DateTime(2026, 5, 20);
      final entries = [
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
      ];

      I18n.setLocale(AppLocale.zh);
      final prompt = DiaryDeepReviewBuilder.build(
        today: today,
        entries: entries,
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

      I18n.setLocale(AppLocale.en);
      final promptWithEnglishLocale = DiaryDeepReviewBuilder.build(
        today: today,
        entries: entries,
      );
      expect(
        promptWithEnglishLocale.systemPrompt,
        contains('Write in English'),
      );
      expect(
        promptWithEnglishLocale.summary,
        contains('2 diary entries in the last 30 days'),
      );
      expect(promptWithEnglishLocale.summary, contains('Good 1'));
      expect(promptWithEnglishLocale.userPrompt, contains('Mood=Good'));
      expect(promptWithEnglishLocale.userPrompt, contains('Weather=Sunny'));
      expect(promptWithEnglishLocale.userPrompt, contains('Location=上海'));
      expect(promptWithEnglishLocale.userPrompt, contains('Tags=工作,散步'));
      expect(promptWithEnglishLocale.userPrompt, contains('今天推进了重要项目'));
      expect(promptWithEnglishLocale.userPrompt, isNot(contains('很久以前的内容')));
      final explicitChinese = DiaryDeepReviewBuilder.build(
        today: today,
        entries: entries,
        locale: AppLocale.zh,
      );
      expect(explicitChinese.systemPrompt, prompt.systemPrompt);
      expect(explicitChinese.summary, prompt.summary);
      expect(explicitChinese.userPrompt, prompt.userPrompt);
    },
  );

  test(
    'Diary title localizes only generated fallback without changing JSON',
    () {
      final emptyDiary = DiaryEntry(
        id: 'empty-diary',
        date: DateTime(2026, 5, 18),
        content: ' \n\t ',
        mood: Mood.good,
        weather: Weather.sunny,
        tags: ['作者标签'],
        imagePaths: ['diary/entry.png'],
        location: '上海',
      );
      final authoredFallbackText = DiaryEntry(
        id: 'authored-fallback-text',
        date: DateTime(2026, 5, 18),
        content: '5月18日的日记\n这是作者写的正文',
        tags: ['原样保留'],
      );
      final emptyJsonBefore = jsonEncode(emptyDiary.toJson());
      final authoredJsonBefore = jsonEncode(authoredFallbackText.toJson());

      I18n.setLocale(AppLocale.zh);
      expect(emptyDiary.titleFor(AppLocale.zh), '5月18日的日记');
      expect(emptyDiary.title, '5月18日的日记');

      I18n.setLocale(AppLocale.en);
      expect(emptyDiary.titleFor(AppLocale.en), 'Diary for 5/18');
      expect(emptyDiary.title, 'Diary for 5/18');
      expect(emptyDiary.titleFor(AppLocale.zh), '5月18日的日记');
      expect(I18n.current, AppLocale.en);

      expect(authoredFallbackText.titleFor(AppLocale.zh), '5月18日的日记');
      expect(authoredFallbackText.titleFor(AppLocale.en), '5月18日的日记');
      expect(authoredFallbackText.title, '5月18日的日记');
      expect(I18n.current, AppLocale.en);
      expect(jsonEncode(emptyDiary.toJson()), emptyJsonBefore);
      expect(jsonEncode(authoredFallbackText.toJson()), authoredJsonBefore);
      expect(emptyDiary.toJson(), isNot(contains('title')));
      expect(authoredFallbackText.toJson(), isNot(contains('title')));
    },
  );
}
