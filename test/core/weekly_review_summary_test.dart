import 'dart:convert';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/weekly_review_summary.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => I18n.setLocale(AppLocale.zh));
  tearDown(() => I18n.setLocale(AppLocale.zh));

  test('weekly stats JSON accepts only nonnegative integer metrics', () {
    const stats = WeeklyReviewStats(
      completedTodos: 3,
      totalTodos: 5,
      focusMinutes: 60,
      habitStreak: 4,
      period: WeeklyReviewPeriod.thisWeek,
    );
    final base = stats.toJson();
    const metrics = [
      'completedTodos',
      'totalTodos',
      'focusMinutes',
      'habitStreak',
    ];
    const invalidValues = <Object?>[-1, 1.0, '1', true, null];

    for (final metric in metrics) {
      for (final invalid in invalidValues) {
        expect(
          WeeklyReviewStats.fromJson(<String, Object?>{
            ...base,
            metric: invalid,
          }),
          isNull,
          reason: '$metric must reject $invalid',
        );
      }
    }

    final zeroStats = WeeklyReviewStats.fromJson(<String, Object?>{
      ...base,
      'completedTodos': 0,
      'totalTodos': 0,
      'focusMinutes': 0,
      'habitStreak': 0,
    });
    expect(zeroStats, isNotNull);

    final completedCanExceedTotal = WeeklyReviewStats.fromJson(
      <String, Object?>{...base, 'completedTodos': 8, 'totalTodos': 3},
    );
    expect(completedCanExceedTotal?.completedTodos, 8);
    expect(completedCanExceedTotal?.totalTodos, 3);
  });

  test('invalid stats metadata leaves saved text and AI content intact', () {
    const summary = 'An authored summary that must remain available.';
    const content =
        'Saved AI prose stays byte-for-byte unchanged.\nSecond line.';
    final entry = AiReviewEntry.fromJson(<String, dynamic>{
      'id': 'malformed-stats',
      'createdAt': DateTime(2026, 10, 15, 9).toIso8601String(),
      'content': content,
      'summary': summary,
      'model': 'fixture',
      'kind': AiService.weeklyReviewKind,
      'weeklyStats': <String, Object?>{
        'completedTodos': 3,
        'totalTodos': 5,
        'focusMinutes': -1,
        'habitStreak': 4,
        'period': 'thisWeek',
      },
    });

    expect(entry.weeklyStats, isNull);
    expect(entry.summary, summary);
    expect(entry.displaySummary, summary);
    expect(entry.content, content);

    const legacySummary = 'last week数据：完成 3 / 5 项待办，专注 60 分钟，习惯连续打卡 4 天。';
    final legacyEntry = AiReviewEntry.fromJson(<String, dynamic>{
      'id': 'malformed-stats-with-legacy-copy',
      'createdAt': DateTime(2026, 10, 15, 9).toIso8601String(),
      'content': content,
      'summary': legacySummary,
      'kind': AiService.weeklyReviewKind,
      'weeklyStats': <String, Object?>{'completedTodos': -1},
    });
    I18n.setLocale(AppLocale.en);
    expect(
      legacyEntry.displaySummary,
      'last week summary: tasks done 3 / 5, focus 60 min, longest habit streak 4 days.',
    );
    expect(legacyEntry.summary, legacySummary);
    expect(legacyEntry.content, content);
  });

  test(
    'complete legacy Chinese and lowercase hybrid summaries are recognized',
    () {
      final cases =
          <({String source, WeeklyReviewPeriod period, String zh, String en})>[
            (
              source: '本周数据：完成 3 / 5 项待办，专注 60 分钟，习惯连续打卡 4 天。',
              period: WeeklyReviewPeriod.thisWeek,
              zh: '本周',
              en: 'this week',
            ),
            (
              source: '上周数据：完成 3 / 5 项待办，专注 60 分钟，习惯连续打卡 4 天。',
              period: WeeklyReviewPeriod.lastWeek,
              zh: '上周',
              en: 'last week',
            ),
            (
              source: 'this week数据：完成 3 / 5 项待办，专注 60 分钟，习惯连续打卡 4 天。',
              period: WeeklyReviewPeriod.thisWeek,
              zh: '本周',
              en: 'this week',
            ),
            (
              source: 'last week数据：完成 3 / 5 项待办，专注 60 分钟，习惯连续打卡 4 天。',
              period: WeeklyReviewPeriod.lastWeek,
              zh: '上周',
              en: 'last week',
            ),
          ];

      for (final item in cases) {
        final parsed = WeeklyReviewStats.fromLegacy(item.source);
        expect(parsed, isNotNull, reason: item.source);
        final stats = parsed!;
        expect(stats.completedTodos, 3);
        expect(stats.totalTodos, 5);
        expect(stats.focusMinutes, 60);
        expect(stats.habitStreak, 4);
        expect(stats.period, item.period);
        expect(
          stats.format(isEnglish: false),
          '${item.zh}数据：完成 3 / 5 项待办，专注 60 分钟，习惯连续打卡 4 天。',
        );
        expect(
          stats.format(isEnglish: true),
          '${item.en} summary: tasks done 3 / 5, focus 60 min, longest habit streak 4 days.',
        );
      }
    },
  );

  test('legacy numbers must be canonical nonnegative integers', () {
    String legacy({
      String completed = '3',
      String total = '5',
      String focus = '60',
      String streak = '4',
    }) => '本周数据：完成 $completed / $total 项待办，专注 $focus 分钟，习惯连续打卡 $streak 天。';

    expect(WeeklyReviewStats.fromLegacy(legacy(completed: '0')), isNotNull);
    for (final invalid in ['00', '03', '-1', '+1', '1.0', '1,000']) {
      expect(
        WeeklyReviewStats.fromLegacy(legacy(completed: invalid)),
        isNull,
        reason: 'completed=$invalid',
      );
      expect(
        WeeklyReviewStats.fromLegacy(legacy(total: invalid)),
        isNull,
        reason: 'total=$invalid',
      );
      expect(
        WeeklyReviewStats.fromLegacy(legacy(focus: invalid)),
        isNull,
        reason: 'focus=$invalid',
      );
      expect(
        WeeklyReviewStats.fromLegacy(legacy(streak: invalid)),
        isNull,
        reason: 'streak=$invalid',
      );
    }

    final moreCompletedThanTotal = WeeklyReviewStats.fromLegacy(
      legacy(completed: '8', total: '3'),
    );
    expect(moreCompletedThanTotal?.completedTodos, 8);
    expect(moreCompletedThanTotal?.totalTodos, 3);
  });

  test(
    'decorated, trailing-newline, unknown and custom text stay unchanged',
    () {
      const complete = '本周数据：完成 3 / 5 项待办，专注 60 分钟，习惯连续打卡 4 天。';
      final unchanged = [
        '$complete\n',
        ' $complete',
        '$complete ',
        '历史：$complete',
        '本周数据（已编辑）：完成 3 / 5 项待办，专注 60 分钟，习惯连续打卡 4 天。',
        'Custom period report: focus on the next milestone.',
      ];

      for (final text in unchanged) {
        expect(WeeklyReviewStats.fromLegacy(text), isNull, reason: text);
        final entry = _entry(summary: text, kind: AiService.weeklyReviewKind);
        expect(entry.displaySummary, text, reason: text);
      }
    },
  );

  test('explicit non-weekly kind prevents legacy localization', () {
    const summary = '本周数据：完成 3 / 5 项待办，专注 60 分钟，习惯连续打卡 4 天。';
    const stats = WeeklyReviewStats(
      completedTodos: 3,
      totalTodos: 5,
      focusMinutes: 60,
      habitStreak: 4,
      period: WeeklyReviewPeriod.thisWeek,
    );
    final entry = _entry(
      summary: summary,
      kind: 'daily_review',
      weeklyStats: stats,
    );

    I18n.setLocale(AppLocale.en);
    expect(entry.displaySummary, summary);
    expect(entry.toJson()['summary'], summary);
  });

  test('custom labels that resemble built-in labels remain authored text', () {
    const englishLookingCustom = WeeklyReviewStats(
      completedTodos: 8,
      totalTodos: 3,
      focusMinutes: 25,
      habitStreak: 2,
      period: WeeklyReviewPeriod.custom,
      customPeriodLabel: 'this week',
    );
    const chineseLookingCustom = WeeklyReviewStats(
      completedTodos: 8,
      totalTodos: 3,
      focusMinutes: 25,
      habitStreak: 2,
      period: WeeklyReviewPeriod.custom,
      customPeriodLabel: '本周',
    );
    final restoredEnglishLookingCustom = WeeklyReviewStats.fromJson(
      englishLookingCustom.toJson(),
    )!;
    final restoredChineseLookingCustom = WeeklyReviewStats.fromJson(
      chineseLookingCustom.toJson(),
    )!;

    I18n.setLocale(AppLocale.zh);
    expect(
      restoredEnglishLookingCustom.format(isEnglish: false),
      'this week数据：完成 8 / 3 项待办，专注 25 分钟，习惯连续打卡 2 天。',
    );
    expect(
      restoredChineseLookingCustom.format(isEnglish: false),
      '本周数据：完成 8 / 3 项待办，专注 25 分钟，习惯连续打卡 2 天。',
    );

    I18n.setLocale(AppLocale.en);
    expect(
      restoredEnglishLookingCustom.format(isEnglish: true),
      'this week summary: tasks done 8 / 3, focus 25 min, longest habit streak 2 days.',
    );
    expect(
      restoredChineseLookingCustom.format(isEnglish: true),
      '本周 summary: tasks done 8 / 3, focus 25 min, longest habit streak 2 days.',
    );
  });

  test('legacy period stays stable while display language changes', () {
    const summary = 'last week数据：完成 8 / 3 项待办，专注 25 分钟，习惯连续打卡 2 天。';
    final entry = _entry(summary: summary, kind: AiService.weeklyReviewKind);

    I18n.setLocale(AppLocale.en);
    expect(
      entry.displaySummary,
      'last week summary: tasks done 8 / 3, focus 25 min, longest habit streak 2 days.',
    );
    I18n.setLocale(AppLocale.zh);
    expect(entry.displaySummary, '上周数据：完成 8 / 3 项待办，专注 25 分钟，习惯连续打卡 2 天。');
    expect(entry.summary, summary);
  });

  test(
    'saved facts and AI content round-trip without persisting translated copy',
    () {
      const originalStats = WeeklyReviewStats(
        completedTodos: 8,
        totalTodos: 3,
        focusMinutes: 125,
        habitStreak: 6,
        period: WeeklyReviewPeriod.lastWeek,
      );
      final original = AiReviewEntry(
        id: 'frozen-weekly-review',
        createdAt: DateTime(2026, 10, 15, 9, 30),
        content: 'AI prose stays byte-exact.\nNo locale rewrite.',
        summary: '上周数据：完成 8 / 3 项待办，专注 125 分钟，习惯连续打卡 6 天。',
        model: 'fixture-model',
        kind: AiService.weeklyReviewKind,
        weeklyStats: originalStats,
      );
      final persisted = Map<String, dynamic>.from(
        jsonDecode(jsonEncode(original.toJson())) as Map,
      );
      final restored = AiReviewEntry.fromJson(persisted);

      expect(restored.toJson(), original.toJson());
      expect(restored.content, original.content);
      expect(restored.summary, original.summary);
      expect(restored.weeklyStats?.completedTodos, 8);
      expect(restored.weeklyStats?.totalTodos, 3);
      expect(restored.weeklyStats?.focusMinutes, 125);
      expect(restored.weeklyStats?.habitStreak, 6);
      expect(restored.weeklyStats?.period, WeeklyReviewPeriod.lastWeek);

      I18n.setLocale(AppLocale.en);
      expect(
        restored.displaySummary,
        'last week summary: tasks done 8 / 3, focus 125 min, longest habit streak 6 days.',
      );
      expect(restored.toJson(), original.toJson());

      I18n.setLocale(AppLocale.zh);
      expect(
        restored.displaySummary,
        '上周数据：完成 8 / 3 项待办，专注 125 分钟，习惯连续打卡 6 天。',
      );
      expect(restored.toJson(), original.toJson());
      expect(restored.content, original.content);
      expect(restored.summary, original.summary);
    },
  );
}

AiReviewEntry _entry({
  required String summary,
  required String kind,
  WeeklyReviewStats? weeklyStats,
}) => AiReviewEntry(
  id: 'fixture-review',
  createdAt: DateTime(2026, 10, 15, 9),
  content: 'unchanged AI content',
  summary: summary,
  kind: kind,
  weeklyStats: weeklyStats,
);
