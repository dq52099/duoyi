import 'package:duoyi/core/habit_insights.dart';
import 'package:duoyi/core/habit_trend.dart';
import 'package:duoyi/core/heatmap_calendar.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/habit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => I18n.setLocale(AppLocale.zh));
  tearDown(() => I18n.setLocale(AppLocale.zh));

  for (final percent in [80, 50, 49]) {
    test('overview threshold $percent is stable across locale changes', () {
      final text = HabitOverviewInsightText(
        window: HabitTrendWindow.days30,
        percent: percent,
        completedDays: percent,
        activeDays: 100,
      );
      final insight = HabitInsight(
        kind: HabitInsightKind.overview,
        title: text.titleFor(AppLocale.zh),
        message: text.messageFor(AppLocale.zh),
        score: percent / 100,
        generatedText: text,
      );
      final chineseTitle = insight.title;
      final chineseMessage = insight.message;
      expect(chineseMessage, '30天平均达标率 $percent%，已完成 $percent/100 个活跃日。');
      I18n.setLocale(AppLocale.en);
      expect(
        insight.title,
        percent >= 80
            ? 'Habits are steady'
            : percent >= 50
            ? 'Room to improve'
            : 'Habits need attention',
      );
      expect(
        insight.message,
        '30 days average completion: $percent%; $percent/100 active days completed.',
      );
      expect(insight.score, percent / 100);
      expect(insight.titleFor(AppLocale.zh), chineseTitle);
      expect(insight.messageFor(AppLocale.zh), chineseMessage);
      expect(I18n.current, AppLocale.en);
    });
  }

  for (final window in HabitTrendWindow.values) {
    test('overview window $window uses typed period in English', () {
      final text = HabitOverviewInsightText(
        window: window,
        percent: 40,
        completedDays: 4,
        activeDays: 10,
      );
      final englishPeriod = window == HabitTrendWindow.days365
          ? '1 year'
          : '${window.days} days';
      expect(
        text.messageFor(AppLocale.en),
        startsWith('$englishPeriod average'),
      );
      expect(text.messageFor(AppLocale.zh), startsWith(window.label));
    });
  }

  test('unmarked literal copy identical to generated text stays literal', () {
    const insight = HabitInsight(
      kind: HabitInsightKind.attention,
      title: '阅读 需要关注',
      message: '当前达标率 20%，可以先改成更小目标，避免连续挫败。',
    );
    I18n.setLocale(AppLocale.en);
    expect(insight.generatedText, isNull);
    expect(insight.title, '阅读 需要关注');
    expect(insight.message, '当前达标率 20%，可以先改成更小目标，避免连续挫败。');
  });

  test(
    'cached engine insights preserve scores, order, IDs and authored names',
    () {
      final today = DateTime(2026, 10, 11);
      final currentStart = today.subtract(const Duration(days: 29));
      final previousStart = currentStart.subtract(const Duration(days: 30));
      Map<String, int> completions(int current, int previous) => {
        for (var i = 0; i < current; i++)
        HeatmapCalendarWindow.dateKey(currentStart.add(Duration(days: i))): 1,
        for (var i = 0; i < previous; i++)
        HeatmapCalendarWindow.dateKey(previousStart.add(Duration(days: i))): 1,
      };
      final habits = [
        Habit(id: 'up', name: '正在变好', completions: completions(18, 4)),
        Habit(id: 'down', name: '需要关注', completions: completions(5, 18)),
      ];
      final json = habits.map((habit) => habit.toJson()).toList();
      final insights = HabitInsightEngine.buildInsights(habits, today: today);
      final facts = [
        for (final insight in insights)
          (insight.kind, insight.habitId, insight.score),
      ];
      final chineseCopy = [
        for (final insight in insights) (insight.title, insight.message),
      ];
      expect(insights.map((insight) => insight.kind), HabitInsightKind.values);
      habits.first.name = 'changed after generation';
      I18n.setLocale(AppLocale.en);
      expect(insights[1].title, '正在变好 is improving');
      expect(insights[2].title, '需要关注 is slipping');
      expect(insights[3].title, '正在变好 has the strongest streak');
      expect(insights[4].title, '需要关注 needs attention');
      expect(insights[1].message, startsWith('Up 47 percentage points'));
      expect(insights[2].message, startsWith('Down 43 percentage points'));
      expect(insights[3].message, contains('18 days'));
      expect(insights[4].message, startsWith('Current completion is 17%'));
      expect([
        for (final insight in insights)
          (insight.kind, insight.habitId, insight.score),
      ], facts);
      habits.first.name = '正在变好';
      expect(habits.map((habit) => habit.toJson()).toList(), json);
      final rebuilt = HabitInsightEngine.buildInsights(habits, today: today);
      expect([
        for (final insight in rebuilt)
          (insight.kind, insight.habitId, insight.score),
      ], facts);
      expect(
        HabitInsightEngine.buildInsights(habits, today: today, limit: 2),
        hasLength(2),
      );
      I18n.setLocale(AppLocale.zh);
      expect([
        for (final insight in insights) (insight.title, insight.message),
      ], chineseCopy);
    },
  );
}
