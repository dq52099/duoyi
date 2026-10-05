import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/goal.dart';
import 'package:duoyi/models/habit.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/habit_detail_screen.dart';
import 'package:duoyi/screens/habit_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('Habit.activeForDate', () {
    test('activeWeekdays=[0,2,4] 时仅周一/三/五生效，周末不生效', () {
      final habit = Habit(
        id: 'active-weekdays',
        name: '一三五习惯',
        activeWeekdays: const [0, 2, 4],
      );
      // 2026-01-05 是周一。
      expect(habit.activeForDate(DateTime(2026, 1, 5)), isTrue); // 周一
      expect(habit.activeForDate(DateTime(2026, 1, 6)), isFalse); // 周二
      expect(habit.activeForDate(DateTime(2026, 1, 7)), isTrue); // 周三
      expect(habit.activeForDate(DateTime(2026, 1, 8)), isFalse); // 周四
      expect(habit.activeForDate(DateTime(2026, 1, 9)), isTrue); // 周五
      expect(habit.activeForDate(DateTime(2026, 1, 10)), isFalse); // 周六
      expect(habit.activeForDate(DateTime(2026, 1, 11)), isFalse); // 周日
    });

    test('默认构造（未传 activeWeekdays）保持全 7 天生效', () {
      final habit = Habit(id: 'default', name: '每天');
      expect(habit.activeWeekdays, [0, 1, 2, 3, 4, 5, 6]);
      for (var day = 5; day <= 11; day++) {
        expect(
          habit.activeForDate(DateTime(2026, 1, day)),
          isTrue,
          reason: '2026-01-$day 应生效',
        );
      }
    });
  });

  group('Habit JSON 兼容', () {
    test('旧 JSON 缺 activeWeekdays 字段时回退全 7 天并显式落盘', () {
      final habit = Habit.fromJson(<String, dynamic>{
        'id': 'legacy',
        'name': '旧数据习惯',
        'kind': 0,
        'targetCount': 1,
      });
      expect(habit.activeWeekdays, [0, 1, 2, 3, 4, 5, 6]);
      for (var day = 5; day <= 11; day++) {
        expect(
          habit.activeForDate(DateTime(2026, 1, day)),
          isTrue,
          reason: '2026-01-$day 应生效',
        );
      }
      // 再次保存时字段显式写入 JSON，云同步/迁移不会丢配置。
      expect(habit.toJson()['activeWeekdays'], [0, 1, 2, 3, 4, 5, 6]);
    });

    test('activeWeekdays 非法项被过滤，仅保留 0-6 的整数', () {
      final habit = Habit.fromJson(<String, dynamic>{
        'id': 'partial',
        'name': '脏数据习惯',
        'activeWeekdays': <dynamic>[0, '2', 9, -1, 'x'],
      });
      expect(habit.activeWeekdays, [0, 2]);
    });
  });

  group('HabitProvider.currentWeekProgress', () {
    test('周完成率分母只数生效日，非生效日的打卡记录不进分母', () async {
      final provider = HabitProvider();
      final now = DateTime.now();
      final monday = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: now.weekday - 1));
      final tuesday = monday.add(const Duration(days: 1));
      final keyHelper = Habit(id: 'key-helper', name: 'helper');
      final rangeStart = monday.subtract(const Duration(days: 14));

      final allWeek = Habit(
        id: 'all-week',
        name: '每天习惯',
        startDate: rangeStart,
      );
      allWeek.completions[keyHelper.dateKey(tuesday)] = 1;

      final mondayOnly = Habit(
        id: 'monday-only',
        name: '仅周一习惯',
        activeWeekdays: const [0],
        startDate: rangeStart,
      );
      // 非生效日（周二）上的历史打卡记录：不应让该习惯进入分母。
      mondayOnly.completions[keyHelper.dateKey(tuesday)] = 1;

      await provider.addHabit(allWeek);
      await provider.addHabit(mondayOnly);

      final progress = provider.currentWeekProgress();
      // 周二只有 all-week 生效：该日 = 1/1 = 1.0。
      // 若 monday-only 泄漏进分母，该日会是 (1 + 0) / 2 = 0.5。
      expect(progress[1], 1.0);
      for (var i = 0; i < 7; i++) {
        if (i == 1) continue;
        expect(progress[i], 0.0, reason: '周内第 ${i + 1} 天不应计入完成率');
      }
    });
  });

  group('生效星期表单入口', () {
    testWidgets('新建表单保存生效星期到 Habit.activeWeekdays', (tester) async {
      final habitProvider = HabitProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<HabitProvider>.value(value: habitProvider),
            ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ],
          child: const MaterialApp(home: HabitScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.text(I18n.tr('habit.active_weekdays')), findsOneWidget);
      // 默认全选（保持历史行为）。
      for (var i = 0; i < 7; i++) {
        final chip = tester.widget<FilterChip>(
          find.byKey(ValueKey('habit_active_weekday_chip_$i')),
        );
        expect(chip.selected, isTrue, reason: 'chip $i 默认应选中');
      }

      await tester.enterText(
        find.widgetWithText(TextField, I18n.tr('habit.field.name')),
        '工作日习惯',
      );
      await tester.pumpAndSettle();

      // 取消勾选"周三"。
      final wednesdayChip = find.byKey(
        const ValueKey('habit_active_weekday_chip_2'),
      );
      await tester.ensureVisible(wednesdayChip);
      await tester.tap(wednesdayChip);
      await tester.pumpAndSettle();

      final saveButton = find.widgetWithText(ElevatedButton, '开启新习惯');
      await tester.ensureVisible(saveButton);
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      final stored = habitProvider.habits.single;
      expect(stored.name, '工作日习惯');
      expect(stored.activeWeekdays, [0, 1, 3, 4, 5, 6]);
    });

    testWidgets('详情编辑：生效星期显式配置，不被每周提醒 weekdays 覆盖', (tester) async {
      final habitProvider = HabitProvider();
      await habitProvider.addHabit(
        Habit(
          id: 'decoupled',
          name: '解耦习惯',
          activeWeekdays: const [0, 2, 4], // 生效日：周一/三/五
          reminderPlan: ReminderPlan(
            enabled: true,
            rules: [
              ReminderRule(
                id: 'habit-weekly',
                enabled: true,
                type: ReminderRuleType.weeklyTime,
                kind: ReminderKind.popup,
                hour: 9,
                minute: 0,
                weekdays: const [2, 4, 6], // 提醒日：周三/五/日
              ),
            ],
          ),
        ),
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<HabitProvider>.value(
          value: habitProvider,
          child: const MaterialApp(
            home: HabitDetailScreen(habitId: 'decoupled'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();

      // 每周提醒存在时，显示"两者相互独立"的提示。
      expect(
        find.text(I18n.tr('habit.active_weekdays.reminder_hint')),
        findsOneWidget,
      );

      // 不改动任何字段直接保存：生效星期保持 [0,2,4]，
      // 不再被提醒 weekdays [2,4,6] 反推覆盖成 [1,3,5]。
      var saveButton = find.widgetWithText(
        FilledButton,
        I18n.tr('action.save'),
      );
      await tester.ensureVisible(saveButton.last);
      await tester.tap(saveButton.last);
      await tester.pumpAndSettle();

      var stored = habitProvider.habits.single;
      expect(stored.activeWeekdays, [0, 2, 4]);

      // 再次打开编辑表单，取消勾选"周一"后保存：显式生效日生效。
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();

      final mondayChip = find.byKey(
        const ValueKey('habit_active_weekday_chip_0'),
      );
      await tester.ensureVisible(mondayChip);
      await tester.tap(mondayChip);
      await tester.pumpAndSettle();

      saveButton = find.widgetWithText(FilledButton, I18n.tr('action.save'));
      await tester.ensureVisible(saveButton.last);
      await tester.tap(saveButton.last);
      await tester.pumpAndSettle();

      stored = habitProvider.habits.single;
      expect(stored.activeWeekdays, [2, 4]);
      // 生效星期的改动不影响提醒计划本身。
      expect(
        stored.reminderPlan.rules.single.type,
        ReminderRuleType.weeklyTime,
      );
      expect(stored.reminderPlan.rules.single.weekdays, [2, 4, 6]);
    });
  });
}
