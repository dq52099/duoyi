import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/habit.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/screens/habit_detail_screen.dart';
import 'package:duoyi/screens/habit_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_support/recording_reminder_scheduler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    I18n.setLocale(AppLocale.en);
  });

  tearDown(() => I18n.setLocale(AppLocale.zh));

  test('count-aware unit and occurrence helpers preserve raw legacy units', () {
    final date = DateTime(2026, 10, 15);
    Habit habitWithCount({
      String? key,
      String? unit,
      int count = 0,
      int target = 2,
      bool hasUnit = false,
    }) => Habit(
      id: 'helper',
      name: 'Helper',
      targetCount: target,
      unit: hasUnit ? unit : null,
      generatedUnitKey: key,
      completions: {dateKey(date): count},
    );

    final cup = habitWithCount(key: 'cup');
    for (final sample in const [
      (count: 0, currentUnit: 'cups', localized: '0 cups / 2 cups'),
      (count: 1, currentUnit: 'cup', localized: '1 cup / 2 cups'),
      (count: 2, currentUnit: 'cups', localized: '2 cups / 2 cups'),
    ]) {
      final habit = habitWithCount(key: 'cup', count: sample.count);
      expect(habitUnit(habit, AppLocale.en, sample.count), sample.currentUnit);
      expect(
        localizedHabitCountForDate(habit, date, AppLocale.en),
        sample.localized,
      );
    }

    final defaultUnit = habitWithCount();
    for (final sample in const [
      (count: 0, currentUnit: 'times', localized: '0 times / 2 times'),
      (count: 1, currentUnit: 'time', localized: '1 time / 2 times'),
      (count: 2, currentUnit: 'times', localized: '2 times / 2 times'),
    ]) {
      final habit = habitWithCount(count: sample.count);
      expect(habitUnit(habit, AppLocale.en, sample.count), sample.currentUnit);
      expect(
        localizedHabitCountForDate(habit, date, AppLocale.en),
        sample.localized,
      );
    }

    final unknownKey = habitWithCount(key: 'future-unit', count: 1);
    expect(habitUnit(unknownKey, AppLocale.en, 1), 'time');
    expect(
      localizedHabitCountForDate(unknownKey, date, AppLocale.en),
      '1 time / 2 times',
    );

    for (final literal in ['', '  ']) {
      final rawBlank = habitWithCount(
        key: 'cup',
        unit: literal,
        count: 1,
        hasUnit: true,
      );
      expect(habitUnit(rawBlank, AppLocale.en, 1), literal);
      expect(habitUnit(rawBlank, AppLocale.zh, 1), literal);
      expect(
        localizedHabitCountForDate(rawBlank, date, AppLocale.en),
        '1 $literal / 2 $literal',
      );
    }

    final flexCup = habitWithCount(
      key: 'cup',
      count: 1,
    ).copyWith(flexTarget: 4, flexPeriod: HabitFlexPeriod.week);
    expect(
      localizedFlexPeriodGoalLabel(flexCup, AppLocale.en),
      'Weekly goal: 4 times/week',
    );
    expect(
      localizedFlexPeriodGoalLabel(flexCup, AppLocale.en),
      isNot(contains('cup')),
    );
    expect(
      localizedHabitCountForDate(flexCup, date, AppLocale.en),
      'Recorded 1 cup · This week 1/4',
    );
    expect(habitUnit(cup, AppLocale.zh, 0), '杯');
    expect(defaultUnit.unit, isNull);
  });

  for (final sample in const [
    (key: null, target: 1, unit: 'time', goal: 'Daily 1 time'),
    (key: null, target: 2, unit: 'times', goal: 'Daily 2 times'),
    (key: 'cup', target: 1, unit: 'cup', goal: 'Daily 1 cup'),
    (key: 'cup', target: 2, unit: 'cups', goal: 'Daily 2 cups'),
  ]) {
    testWidgets(
      'HabitDetailScreen renders ${sample.goal} beside occurrence goal',
      (tester) async {
        final fixture = _Fixture();
        final habit = Habit(
          id: 'detail-${sample.key}-${sample.target}',
          name: 'Target habit',
          targetCount: sample.target,
          generatedUnitKey: sample.key,
          flexTarget: 4,
          flexPeriod: HabitFlexPeriod.week,
        );
        await fixture.pumpDetail(tester, habit);

        expect(
          find.textContaining('Weekly goal: 4 times/week · ${sample.goal}'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'negative habit detail pluralizes generated default time counts',
    (tester) async {
      final today = _dateOnly(DateTime.now());
      final yesterday = today.subtract(const Duration(days: 1));
      final fixture = _Fixture();
      await fixture.pumpDetail(
        tester,
        Habit(
          id: 'negative-counts',
          name: 'Avoid coffee',
          kind: HabitKind.negative,
          completions: {dateKey(today): 2, dateKey(yesterday): 1},
        ),
      );

      expect(find.text('Recorded 2 times'), findsWidgets);
      await tester.scrollUntilVisible(
        find.text('Recorded 1 time'),
        160,
        scrollable: _detailScroll(),
      );
      expect(find.text('Recorded 1 time'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'trend average uses its average count and bucket uses total count',
    (tester) async {
      final today = _dateOnly(DateTime.now());
      final completions = <String, int>{};
      for (var daysAgo = 0; daysAgo < 30; daysAgo++) {
        final date = today.subtract(Duration(days: daysAgo));
        completions[dateKey(date)] = switch (daysAgo) {
          0 => 2,
          1 => 0,
          _ => 1,
        };
      }
      final fixture = _Fixture();
      await fixture.pumpDetail(
        tester,
        Habit(
          id: 'cup-trend',
          name: 'Water trend',
          targetCount: 2,
          generatedUnitKey: 'cup',
          flexTarget: 1,
          flexPeriod: HabitFlexPeriod.week,
          completions: completions,
        ),
      );
      await tester.scrollUntilVisible(
        find.text('Habit trend'),
        160,
        scrollable: _detailScroll(),
      );

      // The 30-day average is one, while one bucket has totalCount two.
      expect(find.text('1.0 cup'), findsOneWidget);
      expect(find.textContaining('· 1 cup'), findsWidgets);
      expect(find.textContaining('· 2 cups'), findsOneWidget);
      expect(find.textContaining('· 0 cups'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('plural trend average can coexist with a singular bucket', (
    tester,
  ) async {
    final today = _dateOnly(DateTime.now());
    final completions = <String, int>{};
    for (var daysAgo = 0; daysAgo < 30; daysAgo++) {
      final date = today.subtract(Duration(days: daysAgo));
      completions[dateKey(date)] = switch (daysAgo) {
        0 => 3,
        1 => 1,
        _ => 2,
      };
    }
    final fixture = _Fixture();
    await fixture.pumpDetail(
      tester,
      Habit(
        id: 'cup-trend-plural-average',
        name: 'Water trend',
        targetCount: 2,
        generatedUnitKey: 'cup',
        flexTarget: 1,
        flexPeriod: HabitFlexPeriod.week,
        completions: completions,
      ),
    );
    await tester.scrollUntilVisible(
      find.text('Habit trend'),
      160,
      scrollable: _detailScroll(),
    );

    // The average is two cups, while one daily bucket contains a single cup.
    expect(find.text('2.0 cups'), findsOneWidget);
    expect(find.textContaining('· 1 cup'), findsOneWidget);
    expect(find.textContaining('· 3 cups'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('recommended weekly frequency pluralizes its occurrence count', (
    tester,
  ) async {
    final fixture = _Fixture();
    await fixture.pumpHabitScreen(tester);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    final runTemplate = find.byWidgetPredicate(
      (widget) =>
          widget is ActionChip &&
          widget.label is Text &&
          ((widget.label as Text).data ?? '').contains(
            'Run 5 km · Weekly goal: 4 times/week',
          ),
    );
    await tester.ensureVisible(runTemplate);
    await tester.pumpAndSettle();
    expect(runTemplate.hitTestable(), findsOneWidget);
    await tester.tap(runTemplate);
    await tester.pumpAndSettle();

    expect(find.textContaining('Weekly goal: 4 times/week'), findsOneWidget);
    expect(_textField(tester, 'Target count').controller!.text, '4');
    expect(tester.takeException(), isNull);
  });
}

class _Fixture {
  final habits = HabitProvider();
  final theme = ThemeProvider();
  final timeAudit = TimeAuditProvider();
  final scheduler = RecordingReminderScheduler();

  _Fixture() {
    habits.timeAudit = timeAudit;
    habits.scheduler = scheduler;
  }

  Future<void> pumpDetail(WidgetTester tester, Habit habit) async {
    await habits.addHabit(habit);
    await _pump(tester, HabitDetailScreen(habitId: habit.id));
    _addCleanup(tester);
  }

  Future<void> pumpHabitScreen(WidgetTester tester) async {
    await _pump(tester, const HabitScreen());
    _addCleanup(tester);
  }

  Future<void> _pump(WidgetTester tester, Widget home) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<HabitProvider>.value(value: habits),
          ChangeNotifierProvider<ThemeProvider>.value(value: theme),
          ChangeNotifierProvider<TimeAuditProvider>.value(value: timeAudit),
        ],
        child: MaterialApp(theme: theme.brand.theme, home: home),
      ),
    );
    await tester.pumpAndSettle();
  }

  void _addCleanup(WidgetTester tester) {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      habits.dispose();
      theme.dispose();
      timeAudit.dispose();
    });
  }
}

TextField _textField(WidgetTester tester, String label) =>
    tester.widget<TextField>(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == label,
      ),
    );

Finder _detailScroll() => find
    .byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    )
    .first;

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

String dateKey(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
