import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:duoyi/models/goal.dart';
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

    expect(find.text('习惯趋势'), findsOneWidget);
    expect(find.text('区间明细'), findsOneWidget);
    expect(find.textContaining('达标'), findsOneWidget);

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

  testWidgets(
    'HabitDetailScreen hides reminder selectors and saves multiple popups',
    (tester) async {
      final provider = HabitProvider();
      await provider.addHabit(
        Habit(
          id: 'water',
          name: '喝水',
          targetCount: 8,
          remind: true,
          remindHour: 8,
          remindMinute: 0,
        ),
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<HabitProvider>.value(
          value: provider,
          child: const MaterialApp(home: HabitDetailScreen(habitId: 'water')),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();

      final addReminder = find.text('添加提醒');
      await tester.ensureVisible(addReminder);
      await tester.tap(addReminder);
      await tester.pumpAndSettle();

      expect(find.text('提醒类型'), findsNothing);
      expect(find.text('提醒方式'), findsNothing);
      expect(find.text('通知'), findsNothing);
      expect(find.text('闹钟'), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, '保存').last);
      await tester.pumpAndSettle();

      final editorSave = find.widgetWithText(FilledButton, '保存');
      await tester.ensureVisible(editorSave.last);
      await tester.tap(editorSave.last);
      await tester.pumpAndSettle();

      final stored = provider.habits.single;
      expect(stored.remind, isTrue);
      expect(stored.reminderPlan.enabled, isTrue);
      expect(stored.reminderPlan.rules, hasLength(2));
      expect(
        stored.reminderPlan.rules.map((rule) => rule.type),
        everyElement(ReminderRuleType.dailyTime),
      );
      expect(
        stored.reminderPlan.rules.map((rule) => rule.kind),
        everyElement(ReminderKind.popup),
      );
    },
  );

  testWidgets('HabitDetailScreen 顶部统计在 320/390/430 下不溢出', (tester) async {
    addTearDown(tester.view.reset);
    final todayKey = Habit(id: 'key-helper', name: 'helper').todayKey();

    for (final width in const [320.0, 390.0, 430.0]) {
      tester.view.physicalSize = Size(width, 760);
      tester.view.devicePixelRatio = 1;
      final provider = HabitProvider();
      await provider.addHabit(
        Habit(
          id: 'habit-long-unit',
          name: '超长习惯名称用于验证详情顶部不会挤压遮挡',
          kind: HabitKind.negative,
          unit: '杯超长单位名称',
          completions: {todayKey: 12},
        ),
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<HabitProvider>.value(
          value: provider,
          child: const MaterialApp(
            home: HabitDetailScreen(habitId: 'habit-long-unit'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('习惯趋势'), findsOneWidget);
      expect(
        find.textContaining('杯超长单位名称'),
        findsWidgets,
        reason: 'width=$width',
      );
      expect(tester.takeException(), isNull, reason: 'width=$width');
    }
  });
}
