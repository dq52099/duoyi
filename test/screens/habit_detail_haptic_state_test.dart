import 'dart:convert';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/habit.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/habit_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    I18n.setLocale(AppLocale.zh);
  });
  tearDown(() => I18n.setLocale(AppLocale.zh));

  for (final hapticsEnabled in [true, false]) {
    testWidgets(
      'date record honors haptics setting when enabled=$hapticsEnabled',
      (tester) async {
        final f = _Fixture();
        await f.pump(tester);
        if (!hapticsEnabled) await f.preferences.setHaptic(false);

        final date = DateTime.now();
        await _scrollToDate(tester, date);
        final record = _recordButton(date);
        await tester.ensureVisible(record);
        await tester.pumpAndSettle();
        await _tapAndDrain(tester, record);

        expect(f.habits.habits.single.countForDate(date), 1);
        expect(await _persistedCount(date), 1);
        expect(
          f.hapticArguments,
          hapticsEnabled ? ['HapticFeedbackType.mediumImpact'] : isEmpty,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'date undo honors haptics setting when enabled=$hapticsEnabled',
      (tester) async {
        final date = DateTime.now();
        final habit = Habit(
          id: 'synthetic',
          name: 'Synthetic habit',
          targetCount: 5,
          completions: {_dateKey(date): 2},
        );
        final f = _Fixture(habit: habit);
        await f.pump(tester);
        if (!hapticsEnabled) await f.preferences.setHaptic(false);

        await _scrollToDate(tester, date);
        final undo = _undoButton(date);
        await tester.ensureVisible(undo);
        await tester.pumpAndSettle();
        await _tapAndDrain(tester, undo);

        expect(f.habits.habits.single.countForDate(date), 1);
        expect(await _persistedCount(date), 1);
        expect(
          f.hapticArguments,
          hapticsEnabled ? ['HapticFeedbackType.selectionClick'] : isEmpty,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('inactive date record remains disabled without haptics', (
    tester,
  ) async {
    final date = DateTime.now();
    final habit = Habit(
      id: 'synthetic',
      name: 'Synthetic habit',
      activeWeekdays: [
        for (var day = 0; day < 7; day++)
          if (day != date.weekday - 1) day,
      ],
    );
    final f = _Fixture(habit: habit);
    await f.pump(tester);

    await _scrollToDate(tester, date);
    final record = _recordButton(date);
    final button = tester.widget<IconButton>(
      find.ancestor(of: record, matching: find.byType(IconButton)).first,
    );
    expect(button.onPressed, isNull);
    expect(f.habits.habits.single.countForDate(date), 0);
    expect(await _persistedCount(date), 0);
    expect(f.hapticArguments, isEmpty);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _tapAndDrain(WidgetTester tester, Finder button) async {
  await tester.runAsync(() async {
    await tester.tap(button);
    await AccountPreferenceWrites.drain();
    await Future<void>.delayed(Duration.zero);
  });
  await tester.pumpAndSettle();
}

Finder _dateRow(DateTime date) => find
    .ancestor(
      of: find.text('${date.month}/${date.day}'),
      matching: find.byType(ListTile),
    )
    .first;

Future<void> _scrollToDate(WidgetTester tester, DateTime date) async {
  await tester.scrollUntilVisible(
    find.text('${date.month}/${date.day}'),
    120,
    scrollable: _detailScroll(),
  );
  await tester.pumpAndSettle();
}

Finder _detailScroll() => find
    .byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    )
    .first;

Finder _recordButton(DateTime date) => find.descendant(
  of: _dateRow(date),
  matching: find.byIcon(Icons.add_circle_outline),
);

Finder _undoButton(DateTime date) =>
    find.descendant(of: _dateRow(date), matching: find.byIcon(Icons.undo));

Future<int> _persistedCount(DateTime date) async {
  final prefs = await SharedPreferences.getInstance();
  final data = prefs.getString('habits');
  if (data == null) return 0;
  final habits = jsonDecode(data) as List<dynamic>;
  final habit = Map<String, dynamic>.from(habits.single as Map);
  final completions = Map<String, dynamic>.from(habit['completions'] as Map);
  return (completions[_dateKey(date)] as num?)?.toInt() ?? 0;
}

String _dateKey(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

class _Fixture {
  _Fixture({Habit? habit})
    : habit =
          habit ??
          Habit(id: 'synthetic', name: 'Synthetic habit', targetCount: 5);

  final Habit habit;
  final habits = HabitProvider();
  final preferences = PreferencesProvider();
  final theme = ThemeProvider();
  final List<Object?> hapticArguments = [];

  Future<void> pump(WidgetTester tester) async {
    // The action drain also uses runAsync. Initialize the provider's queue
    // in that real zone so a completed fake-zone tail cannot block it.
    await tester.runAsync(() => habits.addHabit(habit));
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        hapticArguments.add(call.arguments);
      }
      return null;
    });
    addTearDown(() async {
      await tester.runAsync(AccountPreferenceWrites.drain);
      await tester.pumpWidget(const SizedBox.shrink());
      habits.dispose();
      preferences.dispose();
      theme.dispose();
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      tester.view.reset();
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<HabitProvider>.value(value: habits),
          ChangeNotifierProvider<PreferencesProvider>.value(value: preferences),
          ChangeNotifierProvider<ThemeProvider>.value(value: theme),
        ],
        child: MaterialApp(
          theme: theme.brand.theme,
          home: const HabitDetailScreen(habitId: 'synthetic'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }
}
