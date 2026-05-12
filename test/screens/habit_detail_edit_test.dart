import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:duoyi/models/habit.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/screens/habit_detail_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('HabitDetailScreen 可编辑并保存回 provider', (tester) async {
    final provider = HabitProvider();
    final habit = Habit(
      id: 'habit-1',
      name: '喝水',
      targetCount: 8,
      remind: true,
      remindHour: 8,
      remindMinute: 30,
    );
    await provider.addHabit(habit);

    await tester.pumpWidget(
      ChangeNotifierProvider<HabitProvider>.value(
        value: provider,
        child: const MaterialApp(home: HabitDetailScreen(habitId: 'habit-1')),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, '习惯名称'), '晨练');
    await tester.enterText(find.widgetWithText(TextField, '每日目标次数'), '3');

    final saveBtn = find.widgetWithText(FilledButton, '保存');
    expect(saveBtn, findsOneWidget);
    await tester.ensureVisible(saveBtn);
    await tester.tap(saveBtn);
    await tester.pumpAndSettle();

    expect(find.text('晨练'), findsWidgets);
    final stored = provider.habits.firstWhere((h) => h.id == 'habit-1');
    expect(stored.name, '晨练');
    expect(stored.targetCount, 3);
  });
}
