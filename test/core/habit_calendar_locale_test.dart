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
    HabitKind kind = HabitKind.positive,
    String? unit,
    HabitFlexPeriod? period,
  }) => Habit(
    id: 'habit-locale',
    name: '本周 2/3 用户标题',
    kind: kind,
    unit: unit,
    targetCount: 3,
    flexPeriod: period,
    flexTarget: period == null ? null : 3,
    completions: {dateKey: 2},
    createdAt: date,
    updatedAt: date,
  );

  CalendarEvent aggregate(Habit source) => CalendarAggregator.buildEvents(
    todos: const [],
    habits: [source],
    pomodoroSessions: const [],
    colorScheme: ThemeData().colorScheme,
    now: date,
  ).single;

  for (final kind in HabitKind.values) {
    test('cached $kind count follows locale, raw data stays literal', () {
      final source = habit(kind: kind);
      final event = aggregate(source);
      final snapshot = event.toJson();
      final chinese = kind == HabitKind.positive ? '2 次 / 3 次' : '已记录 2 次';
      final english = kind == HabitKind.positive
          ? '2 times / 3 times'
          : 'Recorded 2 times';
      expect(event.subtitle, chinese);
      expect(event.displayMetadata, isA<HabitDisplayMetadata>());
      I18n.setLocale(AppLocale.en);
      expect(CalendarEventDisplayText.resolveSubtitle(event), english);
      expect(CalendarEventDisplayText.resolveTitle(event), source.name);
      expect(event.subtitle, chinese);
      expect(event.toJson(), snapshot);
      expect(event.sourceId, source.id);
      expect(event.date, date);
      expect(event.isCompleted, source.isCompletedForDate(date));
      expect(aggregate(source).toJson(), snapshot);
      I18n.setLocale(AppLocale.zh);
      expect(CalendarEventDisplayText.resolveSubtitle(event), chinese);
    });
  }

  for (final period in HabitFlexPeriod.values) {
    test('cached $period progress uses immutable count facts', () {
      final source = habit(period: period);
      final event = aggregate(source);
      final snapshot = event.toJson();
      final prefix = period == HabitFlexPeriod.week
          ? 'This week'
          : 'This month';
      source.unit = '改写单位';
      source.completions[dateKey] = 0;
      source.flexTarget = 8;
      source.targetCount = 9;
      source.name = '改写标题';
      I18n.setLocale(AppLocale.en);
      expect(
        CalendarEventDisplayText.resolveSubtitle(event),
        '2 times · $prefix 1/3',
      );
      expect(CalendarEventDisplayText.resolveTitle(event), '本周 2/3 用户标题');
      expect(event.toJson(), snapshot);
      expect(
        CalendarEventDisplayText.resolveSubtitle(
          event.copyWith(hasConflict: true),
        ),
        '2 times · $prefix 1/3',
      );
    });
  }

  for (final unit in ['次', '杯', 'times', '']) {
    test('authored unit "$unit" stays exact in cached display', () {
      final event = aggregate(habit(unit: unit));
      I18n.setLocale(AppLocale.en);
      expect(
        CalendarEventDisplayText.resolveSubtitle(event),
        '2 $unit / 3 $unit',
      );
    });
  }

  test('JSON round trip does not infer generated habit provenance', () {
    final event = aggregate(habit());
    final snapshot = event.toJson();
    expect(snapshot, isNot(contains('displayMetadata')));
    final restored = CalendarEvent.fromJson(snapshot);
    I18n.setLocale(AppLocale.en);
    expect(restored.displayMetadata, isNull);
    expect(CalendarEventDisplayText.resolveSubtitle(restored), event.subtitle);
    expect(restored.toJson(), snapshot);
  });

  test('a copied local event keeps its literal subtitle', () {
    final event = aggregate(habit()).copyWith(type: CalendarEventType.event);
    I18n.setLocale(AppLocale.en);
    expect(event.displayMetadata, isA<HabitDisplayMetadata>());
    expect(CalendarEventDisplayText.resolveSubtitle(event), '2 次 / 3 次');
  });

  test('a raw legacy habit event stays literal without metadata', () {
    final event = CalendarEvent(
      id: 'imported-habit',
      title: '用户标题',
      subtitle: '已记录 2 次',
      date: date,
      type: CalendarEventType.habit,
      color: Colors.green,
    );
    I18n.setLocale(AppLocale.en);
    expect(CalendarEventDisplayText.resolveSubtitle(event), '已记录 2 次');
  });
}
