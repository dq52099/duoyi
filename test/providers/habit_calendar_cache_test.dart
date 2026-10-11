import 'package:duoyi/core/calendar_event_display_text.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/habit.dart';
import 'package:duoyi/providers/calendar_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => I18n.setLocale(AppLocale.zh));
  tearDown(() => I18n.setLocale(AppLocale.zh));

  Habit source() => Habit(
    id: 'cached',
    name: 'User habit',
    targetCount: 2,
    completions: {'2026-10-11': 1},
  );

  void rebuild(CalendarProvider provider, Habit habit) =>
      provider.rebuild(const [], [habit], const [], const ColorScheme.light());

  test('a rule-only edit refreshes cached calendar progress', () {
    final provider = CalendarProvider();
    addTearDown(provider.dispose);
    final habit = source();
    rebuild(provider, habit);
    expect(provider.events.single.subtitle, '1 次 / 2 次');
    rebuild(
      provider,
      habit.copyWith(flexTarget: 3, flexPeriod: HabitFlexPeriod.week),
    );
    expect(provider.events.single.subtitle, '1 次 · 本周 1/3');
    rebuild(
      provider,
      habit.copyWith(flexTarget: 4, flexPeriod: HabitFlexPeriod.week),
    );
    expect(provider.events.single.subtitle, '1 次 · 本周 1/4');
    rebuild(
      provider,
      habit.copyWith(flexTarget: 4, flexPeriod: HabitFlexPeriod.month),
    );
    expect(provider.events.single.subtitle, '1 次 · 本月 1/4');
    I18n.setLocale(AppLocale.en);
    expect(
      CalendarEventDisplayText.resolveSubtitle(provider.events.single),
      '1 time · This month 1/4',
    );
  });

  test('same Chinese raw subtitle still notifies on authored unit change', () {
    final provider = CalendarProvider();
    addTearDown(provider.dispose);
    final habit = source();
    rebuild(provider, habit);
    final beforeJson = provider.events.single.toJson();
    var notifications = 0;
    provider.addListener(() => notifications++);
    I18n.setLocale(AppLocale.en);
    expect(
      CalendarEventDisplayText.resolveSubtitle(provider.events.single),
      '1 time / 2 times',
    );
    rebuild(provider, habit.copyWith(unit: '次'));
    expect(notifications, 1);
    expect(provider.events.single.toJson(), beforeJson);
    expect(
      CalendarEventDisplayText.resolveSubtitle(provider.events.single),
      '1 次 / 2 次',
    );
    rebuild(provider, habit);
    expect(notifications, 2);
    expect(
      CalendarEventDisplayText.resolveSubtitle(provider.events.single),
      '1 time / 2 times',
    );
  });

  test('equal display facts suppress redundant calendar notifications', () {
    final provider = CalendarProvider();
    addTearDown(provider.dispose);
    final habit = source();
    rebuild(provider, habit);
    var notifications = 0;
    provider.addListener(() => notifications++);
    // A legacy weekly target is hashed but unused by this daily habit.
    rebuild(provider, habit.copyWith(weeklyTarget: 3));
    expect(notifications, 0);
    expect(provider.events.single.subtitle, '1 次 / 2 次');
  });
}
