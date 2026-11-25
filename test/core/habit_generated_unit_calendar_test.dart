import 'package:duoyi/core/calendar_aggregator.dart';
import 'package:duoyi/core/calendar_event_display_text.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/calendar_event.dart';
import 'package:duoyi/models/habit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final date = DateTime(2026, 10, 11);
  const dateKey = '2026-10-11';

  setUp(() => I18n.setLocale(AppLocale.zh));
  tearDown(() => I18n.setLocale(AppLocale.zh));

  Habit habit({
    String id = 'generated-calendar-habit',
    HabitKind kind = HabitKind.positive,
    String? unit,
    String? generatedUnitKey,
    int count = 2,
    int target = 3,
    HabitFlexPeriod? period,
    int? flexTarget,
    Map<String, int>? completions,
  }) => Habit(
    id: id,
    name: 'User title 本周 2/3',
    kind: kind,
    unit: unit,
    generatedUnitKey: generatedUnitKey,
    targetCount: target,
    flexPeriod: period,
    flexTarget: period == null ? null : flexTarget ?? 3,
    completions: completions ?? {dateKey: count},
    createdAt: date,
    updatedAt: date,
  );

  CalendarEvent aggregate(Habit source, {String eventDateKey = dateKey}) =>
      CalendarAggregator.buildEvents(
        todos: const [],
        habits: [source],
        pomodoroSessions: const [],
        colorScheme: ThemeData().colorScheme,
        now: date,
      ).singleWhere((event) => event.dateKey == eventDateKey);

  test(
    'calendar metadata localizes generated cups and keeps count pluralization',
    () {
      final cases = <({int count, int target, String zh, String en})>[
        (count: 0, target: 1, zh: '0 杯 / 1 杯', en: '0 cups / 1 cup'),
        (count: 1, target: 2, zh: '1 杯 / 2 杯', en: '1 cup / 2 cups'),
        (count: 2, target: 1, zh: '2 杯 / 1 杯', en: '2 cups / 1 cup'),
      ];

      for (final sample in cases) {
        final source = habit(
          id: 'calendar-cup-${sample.count}-${sample.target}',
          count: sample.count,
          target: sample.target,
          generatedUnitKey: 'cup',
        );
        final event = aggregate(source);
        final jsonBefore = event.toJson();
        final metadata = event.displayMetadata! as HabitDisplayMetadata;

        expect(event.subtitle, sample.zh);
        expect(metadata.count, sample.count);
        expect(metadata.targetCount, sample.target);
        expect(metadata.unit, isNull);
        expect(metadata.generatedUnitKey, 'cup');

        I18n.setLocale(AppLocale.en);
        expect(CalendarEventDisplayText.resolveSubtitle(event), sample.en);
        expect(CalendarEventDisplayText.resolveTitle(event), source.name);
        expect(event.subtitle, sample.zh);
        expect(event.toJson(), jsonBefore);
        expect(aggregate(source).toJson(), jsonBefore);
        I18n.setLocale(AppLocale.zh);
        expect(CalendarEventDisplayText.resolveSubtitle(event), sample.zh);
      }
    },
  );

  test(
    'negative and unknown generated units use recorded and fallback labels',
    () {
      final negative = aggregate(
        habit(
          id: 'negative-cup-calendar',
          kind: HabitKind.negative,
          count: 1,
          target: 2,
          generatedUnitKey: 'cup',
        ),
      );
      final unknown = aggregate(
        habit(
          id: 'unknown-unit-calendar',
          count: 2,
          target: 1,
          generatedUnitKey: 'not-a-known-unit',
        ),
      );

      expect(negative.subtitle, '已记录 1 杯');
      expect(
        (negative.displayMetadata! as HabitDisplayMetadata).generatedUnitKey,
        'cup',
      );
      expect(unknown.subtitle, '2 次 / 1 次');
      expect(
        (unknown.displayMetadata! as HabitDisplayMetadata).generatedUnitKey,
        'not-a-known-unit',
      );

      I18n.setLocale(AppLocale.en);
      expect(
        CalendarEventDisplayText.resolveSubtitle(negative),
        'Recorded 1 cup',
      );
      expect(
        CalendarEventDisplayText.resolveSubtitle(unknown),
        '2 times / 1 time',
      );
    },
  );

  test(
    'flex event metadata combines cup counts with weekly and monthly totals',
    () {
      final weeklySource = habit(
        id: 'weekly-cup-calendar',
        count: 2,
        generatedUnitKey: 'cup',
        period: HabitFlexPeriod.week,
        flexTarget: 5,
        completions: {'2026-10-10': 4, dateKey: 2},
      );
      final monthlySource = habit(
        id: 'monthly-cup-calendar',
        count: 2,
        generatedUnitKey: 'cup',
        period: HabitFlexPeriod.month,
        flexTarget: 4,
        completions: {'2026-10-01': 1, dateKey: 2},
      );
      final weekly = aggregate(weeklySource);
      final monthly = aggregate(monthlySource);

      expect(weekly.subtitle, '2 杯 · 本周 2/5');
      expect(monthly.subtitle, '2 杯 · 本月 2/4');
      expect(
        (weekly.displayMetadata! as HabitDisplayMetadata)
            .flexProgress
            ?.completed,
        2,
      );
      expect(
        (monthly.displayMetadata! as HabitDisplayMetadata)
            .flexProgress
            ?.completed,
        2,
      );

      I18n.setLocale(AppLocale.en);
      expect(
        CalendarEventDisplayText.resolveSubtitle(weekly),
        '2 cups · This week 2/5',
      );
      expect(
        CalendarEventDisplayText.resolveSubtitle(monthly),
        '2 cups · This month 2/4',
      );
    },
  );

  test(
    'literal units remain exact even when generated metadata is present',
    () {
      for (final literal in <String>['', '  ', '次', 'times', 'cup']) {
        final event = aggregate(
          habit(
            id: 'literal-calendar-${literal.hashCode}',
            unit: literal,
            generatedUnitKey: 'cup',
            count: 2,
            target: 1,
          ),
        );
        final metadata = event.displayMetadata! as HabitDisplayMetadata;

        expect(metadata.unit, literal);
        expect(metadata.generatedUnitKey, 'cup');
        I18n.setLocale(AppLocale.en);
        expect(
          CalendarEventDisplayText.resolveSubtitle(event),
          '2 $literal / 1 $literal',
        );
      }
    },
  );

  test(
    'generated metadata remains display-only and legacy events stay literal',
    () {
      final event = aggregate(
        habit(
          id: 'serialized-cup-calendar',
          count: 2,
          target: 3,
          generatedUnitKey: 'cup',
        ),
      );
      final snapshot = event.toJson();

      expect(snapshot, isNot(contains('displayMetadata')));
      expect(snapshot, isNot(contains('generatedUnitKey')));
      final restored = CalendarEvent.fromJson(snapshot);
      expect(restored.displayMetadata, isNull);

      final legacyEvent = CalendarEvent(
        id: 'legacy-habit-event',
        title: 'User title',
        subtitle: '已记录 2 次',
        date: date,
        type: CalendarEventType.habit,
        color: Colors.green,
      );
      I18n.setLocale(AppLocale.en);
      expect(
        CalendarEventDisplayText.resolveSubtitle(restored),
        event.subtitle,
      );
      expect(CalendarEventDisplayText.resolveSubtitle(legacyEvent), '已记录 2 次');
    },
  );
}
