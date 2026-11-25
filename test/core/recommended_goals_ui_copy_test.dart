import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/i18n_date_format.dart';
import 'package:duoyi/core/recommended_goals.dart';
import 'package:duoyi/core/recommended_goals_ui_copy.dart';
import 'package:duoyi/models/goal.dart';
import 'package:duoyi/models/recurrence.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => I18n.setLocale(AppLocale.zh));

  test('All built-in English cards have translated metadata', () {
    I18n.setLocale(AppLocale.en);
    for (final item in RecommendedGoalsLibrary.all()) {
      final labels = [
        item.localizedTitle,
        item.localizedDescription,
        RecommendedGoalsUiCopy.category(item.category),
        RecommendedGoalsUiCopy.recurrence(item.recurrence, item.scheduling),
        RecommendedGoalsUiCopy.focus(item.focusLink.focusSeconds),
        RecommendedGoalsUiCopy.reminder(item.reminder),
      ];
      expect(labels.join(' '), isNot(matches(RegExp(r'[\u3400-\u9fff]'))));
      expect(labels.every((label) => label.isNotEmpty), isTrue);
    }
    expect(RecommendedGoalsUiCopy.title, 'Recommended goals');
    expect(RecommendedGoalsUiCopy.skipHolidays, 'Skip holidays');
  });

  test('Fixed weekdays preserve ISO order and translate only the display', () {
    final days = [6, 0, 2];
    final schedule = GoalScheduling.fixed(fixedWeekdays: days);
    const rule = RecurrenceRule(frequency: RecurrenceFrequency.weekly);
    I18n.setLocale(AppLocale.en);
    expect(
      RecommendedGoalsUiCopy.recurrence(rule, schedule),
      'Every week · Mon/Wed/Sun',
    );
    I18n.setLocale(AppLocale.zh);
    expect(RecommendedGoalsUiCopy.recurrence(rule, schedule), '每周 · 周一/三/日');
    expect(days, [6, 0, 2]);
  });

  test('Repeat intervals, month days and random limits use English copy', () {
    I18n.setLocale(AppLocale.en);
    const fixed = GoalScheduling.fixed();
    for (final frequency in RecurrenceFrequency.values) {
      expect(
        RecommendedGoalsUiCopy.recurrence(
          RecurrenceRule(frequency: frequency, interval: 2),
          fixed,
        ),
        isNot(matches(RegExp(r'[\u3400-\u9fff]'))),
      );
    }
    const monthly = RecurrenceRule(frequency: RecurrenceFrequency.monthly);
    expect(
      RecommendedGoalsUiCopy.recurrence(
        monthly,
        const GoalScheduling.fixed(fixedMonthDays: [20, 1]),
      ),
      'Every month · Days 1/20',
    );
    expect(
      RecommendedGoalsUiCopy.recurrence(
        monthly,
        const GoalScheduling.random(maxPerWeek: 3),
      ),
      contains('up to 3/week'),
    );
    expect(
      RecommendedGoalsUiCopy.recurrence(
        monthly,
        const GoalScheduling.random(maxPerMonth: 5),
      ),
      contains('up to 5/month'),
    );
    expect(
      RecommendedGoalsUiCopy.recurrence(
        monthly,
        const GoalScheduling.random(minGapDays: 4),
      ),
      contains('≥4 days apart'),
    );
  });

  test('Every reminder kind has explicit copy and retains its time', () {
    I18n.setLocale(AppLocale.en);
    for (final kind in ReminderKind.values) {
      final label = RecommendedGoalsUiCopy.reminder(
        ReminderConfig(enabled: true, kind: kind, hour: 9, minute: 5),
      );
      expect(label, contains(I18nDateFormat.timeOfDay(hour: 9, minute: 5)));
      expect(label, isNot(matches(RegExp(r'[\u3400-\u9fff]'))));
    }
    expect(RecommendedGoalsUiCopy.duration(3660), '1h 1min');
    expect(RecommendedGoalsUiCopy.duration(45), '45s');
    expect(RecommendedGoalsUiCopy.focus(null), 'Focus');
  });

  test('Language switching never rewrites recommendation payloads', () {
    final items = RecommendedGoalsLibrary.all();
    final before = items.map((item) => (item.title, item.description)).toList();
    for (final locale in [AppLocale.en, AppLocale.zh, AppLocale.en]) {
      I18n.setLocale(locale);
      for (final item in items) {
        RecommendedGoalsUiCopy.recurrence(item.recurrence, item.scheduling);
        RecommendedGoalsUiCopy.reminder(item.reminder);
        item.localizedTitle;
      }
    }
    expect(
      items.map((item) => (item.title, item.description)).toList(),
      before,
    );
  });
}
