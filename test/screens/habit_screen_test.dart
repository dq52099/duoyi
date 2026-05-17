import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:duoyi/models/habit.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/habit_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('negative habit count uses custom unit on main habit card', (
    tester,
  ) async {
    final habitProvider = HabitProvider();
    final dateKey = Habit(id: 'key-helper', name: 'helper').todayKey();
    await habitProvider.addHabit(
      Habit(
        id: 'coffee',
        name: '少喝咖啡',
        kind: HabitKind.negative,
        unit: '杯',
        completions: {dateKey: 1},
      ),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<HabitProvider>.value(value: habitProvider),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ],
        child: const MaterialApp(home: HabitScreen()),
      ),
    );

    expect(find.text('1 杯'), findsOneWidget);
    expect(find.text('1 次'), findsNothing);
  });
}
