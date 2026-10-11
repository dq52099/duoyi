import 'dart:convert';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/habit.dart';
import 'package:test/test.dart';

void main() {
  final date = DateTime(2026, 5, 15);
  const dateKey = '2026-05-15';
  late AppLocale savedLocale;

  setUp(() {
    savedLocale = I18n.current;
    I18n.setLocale(AppLocale.zh);
  });
  tearDown(() => I18n.setLocale(savedLocale));

  group('HabitFlexProgress localization', () {
    for (final period in HabitFlexPeriod.values) {
      test(
        '$period labels support explicit locale and live locale changes',
        () {
          final progress = HabitFlexProgress(
            period: period,
            start: DateTime(2026, 5, 1),
            end: DateTime(2026, 5, 31),
            completed: 2,
            target: 3,
          );
          final zhPrefix = period == HabitFlexPeriod.week ? '本周' : '本月';
          final enPrefix = period == HabitFlexPeriod.week
              ? 'This week'
              : 'This month';

          expect(progress.labelPrefixFor(AppLocale.zh), zhPrefix);
          expect(progress.labelFor(AppLocale.zh), '$zhPrefix 2/3');
          expect(progress.labelPrefixFor(AppLocale.en), enPrefix);
          expect(progress.labelFor(AppLocale.en), '$enPrefix 2/3');
          expect(I18n.current, AppLocale.zh);

          expect(progress.labelPrefix, zhPrefix);
          expect(progress.label, '$zhPrefix 2/3');
          I18n.setLocale(AppLocale.en);
          expect(progress.labelPrefix, enPrefix);
          expect(progress.label, '$enPrefix 2/3');

          expect(progress.labelFor(AppLocale.zh), '$zhPrefix 2/3');
          expect(I18n.current, AppLocale.en);
        },
      );
    }
  });

  test(
    'flex goal labels preserve Chinese and localize week and month goals',
    () {
      final weekly = Habit(
        id: 'weekly-goal',
        name: '跑步',
        flexTarget: 5,
        flexPeriod: HabitFlexPeriod.week,
      );
      final monthly = Habit(
        id: 'monthly-goal',
        name: '游泳',
        flexTarget: 2,
        flexPeriod: HabitFlexPeriod.month,
      );
      final weeklySingular = Habit(
        id: 'weekly-single-goal',
        name: '散步',
        flexTarget: 1,
        flexPeriod: HabitFlexPeriod.week,
      );
      final monthlySingular = Habit(
        id: 'monthly-single-goal',
        name: '读书',
        flexTarget: 1,
        flexPeriod: HabitFlexPeriod.month,
      );
      final daily = Habit(id: 'daily-goal', name: '阅读', weeklyTarget: 5);

      expect(weekly.flexPeriodGoalLabelFor(AppLocale.zh), '每周目标: 5 次/周');
      expect(monthly.flexPeriodGoalLabelFor(AppLocale.zh), '每月目标: 2 次/月');
      expect(
        monthlySingular.flexPeriodGoalLabelFor(AppLocale.zh),
        '每月目标: 1 次/月',
      );
      expect(
        weekly.flexPeriodGoalLabelFor(AppLocale.en),
        'Weekly goal: 5 times/week',
      );
      expect(
        monthly.flexPeriodGoalLabelFor(AppLocale.en),
        'Monthly goal: 2 times/month',
      );
      expect(
        weeklySingular.flexPeriodGoalLabelFor(AppLocale.en),
        'Weekly goal: 1 time/week',
      );
      expect(
        monthlySingular.flexPeriodGoalLabelFor(AppLocale.en),
        'Monthly goal: 1 time/month',
      );
      expect(daily.hasFlexRule, isFalse);
      expect(daily.flexPeriodGoalLabelFor(AppLocale.zh), isEmpty);
      expect(daily.flexPeriodGoalLabelFor(AppLocale.en), isEmpty);
      expect(I18n.current, AppLocale.zh);

      expect(weekly.flexPeriodGoalLabel, '每周目标: 5 次/周');
      expect(monthly.flexPeriodGoalLabel, '每月目标: 2 次/月');
      I18n.setLocale(AppLocale.en);
      expect(weekly.flexPeriodGoalLabel, 'Weekly goal: 5 times/week');
      expect(monthly.flexPeriodGoalLabel, 'Monthly goal: 2 times/month');
    },
  );

  test('positive count labels localize defaults and pluralize each count', () {
    final oneOfTwo = Habit(
      id: 'positive-one-of-two',
      name: '阅读',
      targetCount: 2,
      completions: {dateKey: 1},
    );
    final twoOfOne = Habit(
      id: 'positive-two-of-one',
      name: '喝水',
      targetCount: 1,
      completions: {dateKey: 2},
    );

    expect(oneOfTwo.formatCountForDate(date), '1 次 / 2 次');
    expect(
      oneOfTwo.formatCountForDate(date, locale: AppLocale.en),
      '1 time / 2 times',
    );
    expect(
      twoOfOne.formatCountForDate(date, locale: AppLocale.en),
      '2 times / 1 time',
    );
    expect(I18n.current, AppLocale.zh);

    I18n.setLocale(AppLocale.en);
    expect(oneOfTwo.formatCountForDate(date), '1 time / 2 times');
    expect(
      oneOfTwo.formatCountForDate(date, locale: AppLocale.zh),
      '1 次 / 2 次',
    );
    expect(I18n.current, AppLocale.en);
  });

  test('negative count labels localize recorded counts and singular units', () {
    final one = Habit(
      id: 'negative-one',
      name: '少刷短视频',
      kind: HabitKind.negative,
      completions: {dateKey: 1},
    );
    final two = Habit(
      id: 'negative-two',
      name: '少刷短视频',
      kind: HabitKind.negative,
      completions: {dateKey: 2},
    );

    expect(one.formatCountForDate(date), '已记录 1 次');
    expect(
      one.formatCountForDate(date, locale: AppLocale.en),
      'Recorded 1 time',
    );
    expect(
      two.formatCountForDate(date, locale: AppLocale.en),
      'Recorded 2 times',
    );
    I18n.setLocale(AppLocale.en);
    expect(one.formatCountForDate(date), 'Recorded 1 time');
    expect(one.formatCountForDate(date, locale: AppLocale.zh), '已记录 1 次');
    expect(I18n.current, AppLocale.en);
  });

  test('flex count labels localize week and month progress', () {
    final weekly = Habit(
      id: 'weekly-progress',
      name: '跑步',
      flexTarget: 3,
      flexPeriod: HabitFlexPeriod.week,
      completions: {'2026-05-12': 1, dateKey: 2},
    );
    final monthly = Habit(
      id: 'monthly-progress',
      name: '游泳',
      flexTarget: 1,
      flexPeriod: HabitFlexPeriod.month,
      completions: {dateKey: 1},
    );

    expect(weekly.formatCountForDate(date), '2 次 · 本周 2/3');
    expect(
      weekly.formatCountForDate(date, locale: AppLocale.en),
      '2 times · This week 2/3',
    );
    expect(
      monthly.formatCountForDate(date, locale: AppLocale.en),
      '1 time · This month 1/1',
    );

    I18n.setLocale(AppLocale.en);
    expect(weekly.formatCountForDate(date), '2 times · This week 2/3');
    expect(
      weekly.formatCountForDate(date, locale: AppLocale.zh),
      '2 次 · 本周 2/3',
    );
    expect(I18n.current, AppLocale.en);

    final authoredUnit = weekly.copyWith(unit: '次');
    expect(
      authoredUnit.formatCountForDate(date, locale: AppLocale.en),
      '2 次 · This week 2/3',
    );
  });

  test('flex rule outside the date range displays only the recorded count', () {
    final habit = Habit(
      id: 'out-of-range-flex',
      name: '阶段跑步',
      flexTarget: 3,
      flexPeriod: HabitFlexPeriod.week,
      startDate: DateTime(2026, 5, 12),
      endDate: DateTime(2026, 5, 18),
      completions: {'2026-05-11': 1},
    );
    final beforeStart = DateTime(2026, 5, 11);

    expect(habit.hasFlexRule, isTrue);
    expect(habit.flexProgressForDate(beforeStart), isNull);
    expect(habit.formatCountForDate(beforeStart), '1 次');
    expect(
      habit.formatCountForDate(beforeStart, locale: AppLocale.en),
      '1 time',
    );
    expect(
      habit.formatCountForDate(beforeStart, locale: AppLocale.en),
      isNot(contains('/')),
    );
  });

  test('authored units and habit JSON remain unchanged in every locale', () {
    var unitIndex = 0;
    for (final unit in ['次', '杯', '']) {
      final habit = Habit(
        id: 'authored-unit-${unitIndex++}',
        name: '每天阅读',
        unit: unit,
        category: '习惯记录',
        tags: const ['作者标签'],
        targetCount: 3,
        completions: {dateKey: 2},
        createdAt: DateTime(2026, 5, 1, 9),
        updatedAt: DateTime(2026, 5, 15, 9),
      );
      final jsonBefore = jsonEncode(habit.toJson());

      for (final locale in AppLocale.values) {
        I18n.setLocale(locale);
        expect(habit.formatCountForDate(date), '2 $unit / 3 $unit');
        expect(habit.unit, unit);
        expect(habit.name, '每天阅读');
        expect(habit.category, '习惯记录');
        expect(habit.tags, ['作者标签']);
        expect(jsonEncode(habit.toJson()), jsonBefore);
      }

      final restored = Habit.fromJson(
        Map<String, dynamic>.from(jsonDecode(jsonBefore) as Map),
      );
      expect(restored.unit, unit);
      expect(jsonEncode(restored.toJson()), jsonBefore);
    }
  });

  test('locale changes do not alter progress or period date algorithms', () {
    final weekly = Habit(
      id: 'weekly-algorithm',
      name: '阶段跑步',
      flexTarget: 3,
      flexPeriod: HabitFlexPeriod.week,
      startDate: DateTime(2026, 5, 12),
      endDate: DateTime(2026, 5, 15),
      completions: {'2026-05-11': 1, '2026-05-12': 1, '2026-05-13': 2},
    );
    final friday = DateTime(2026, 5, 15);
    final weekBounds = weekly.periodBoundsForDate(friday);
    final previousWeek = weekly.previousPeriodBounds(weekBounds);
    final monthly = Habit(
      id: 'monthly-algorithm',
      name: '阶段游泳',
      flexTarget: 1,
      flexPeriod: HabitFlexPeriod.month,
      completions: {dateKey: 1},
    );
    final monthBounds = monthly.periodBoundsForDate(date);
    final previousMonth = monthly.previousPeriodBounds(monthBounds);
    final daily = Habit(
      id: 'daily-algorithm',
      name: '阅读',
      targetCount: 2,
      completions: {dateKey: 1},
    );

    expect(weekly.dateKey(friday), dateKey);
    expect(weekBounds.start, DateTime(2026, 5, 11));
    expect(weekBounds.end, DateTime(2026, 5, 17));
    expect(previousWeek.start, DateTime(2026, 5, 4));
    expect(previousWeek.end, DateTime(2026, 5, 10));
    expect(monthBounds.start, DateTime(2026, 5, 1));
    expect(monthBounds.end, DateTime(2026, 5, 31));
    expect(previousMonth.start, DateTime(2026, 4, 1));
    expect(previousMonth.end, DateTime(2026, 4, 30));

    for (final locale in AppLocale.values) {
      I18n.setLocale(locale);
      final weeklyProgress = weekly.flexProgressForDate(friday)!;
      expect(weekly.activeForDate(friday), isTrue);
      expect(
        weekly.completionCountInRange(weekBounds.start, weekBounds.end),
        2,
      );
      expect(weeklyProgress.completed, 2);
      expect(weeklyProgress.target, 3);
      expect(weeklyProgress.ratio, closeTo(2 / 3, 1e-12));
      expect(weekly.progressForDate(friday), closeTo(2 / 3, 1e-12));
      expect(weekly.isCompletedForDate(friday), isFalse);
      expect(
        weekly.completionDatesInRange(weekBounds.start, weekBounds.end),
        isEmpty,
      );

      final monthlyProgress = monthly.flexProgressForDate(date)!;
      expect(
        monthly.completionCountInRange(monthBounds.start, monthBounds.end),
        1,
      );
      expect(monthlyProgress.completed, 1);
      expect(monthlyProgress.isCompleted, isTrue);
      expect(
        monthly.completionDatesInRange(monthBounds.start, monthBounds.end),
        [DateTime(2026, 5, 15, 12)],
      );

      expect(daily.progressForDate(date), 0.5);
      expect(daily.isCompletedForDate(date), isFalse);
      expect(daily.completionDatesInRange(date, date), isEmpty);
    }

    weekly.completions['2026-05-15'] = 1;
    expect(weekly.completionCountInRange(weekBounds.start, weekBounds.end), 3);
    expect(weekly.progressForDate(friday), 1.0);
    expect(weekly.isCompletedForDate(friday), isTrue);
    expect(weekly.completionDatesInRange(weekBounds.start, weekBounds.end), [
      DateTime(2026, 5, 15, 12),
    ]);
  });
}
