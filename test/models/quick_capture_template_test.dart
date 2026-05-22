import 'package:flutter_test/flutter_test.dart';

import 'package:duoyi/models/goal.dart'
    show ReminderKind, ReminderPlan, ReminderRule, ReminderRuleType;
import 'package:duoyi/models/habit.dart';
import 'package:duoyi/models/quick_capture_template.dart';
import 'package:duoyi/models/todo.dart';

void main() {
  test(
    'todo template applies prefix, tags, priority, list and reminder plan',
    () {
      final template = QuickCaptureTemplate(
        name: '工作会议',
        kind: QuickCaptureTemplateKind.todo,
        titlePrefix: '会议',
        tags: const ['工作', '#会议', '工作'],
        priority: TodoPriority.high,
        listGroupName: '工作',
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'before-15',
              type: ReminderRuleType.relativeToDue,
              kind: ReminderKind.alarm,
              offsetMinutes: -15,
            ),
          ],
        ),
      );

      final todo = template.toTodo('明天下午3点 周会');

      expect(todo.title, '会议 周会');
      expect(todo.priority, TodoPriority.high);
      expect(todo.listGroupName, '工作');
      expect(todo.tags, ['工作', '会议']);
      expect(todo.reminderPlan.enabled, isTrue);
      expect(todo.reminderPlan.rules.single.offsetMinutes, -15);
      expect(
        todo.reminderPlan.rules.single.type,
        ReminderRuleType.relativeToDue,
      );
      expect(todo.hasReminder, isTrue);
    },
  );

  test(
    'habit template creates habit with target, category, unit and reminder',
    () {
      final template = QuickCaptureTemplate(
        name: '每日阅读',
        kind: QuickCaptureTemplateKind.habit,
        titlePrefix: '每日阅读',
        tags: const ['学习'],
        habitCategory: '学习提升',
        habitTargetCount: 30,
        habitUnit: '分钟',
        habitKind: HabitKind.positive,
        habitColorValue: 0xFF7E57C2,
        habitRemind: true,
        habitRemindHour: 21,
        habitRemindMinute: 0,
      );

      final habit = template.toHabit('');

      expect(habit.name, '每日阅读');
      expect(habit.tags, ['学习']);
      expect(habit.category, '学习提升');
      expect(habit.targetCount, 30);
      expect(habit.unit, '分钟');
      expect(habit.kind, HabitKind.positive);
      expect(habit.colorValue, 0xFF7E57C2);
      expect(habit.remind, isTrue);
      expect(habit.remindHour, 21);
      expect(habit.remindMinute, 0);
    },
  );

  test('template JSON roundtrip preserves custom defaults', () {
    final original = QuickCaptureTemplate(
      name: '采购',
      kind: QuickCaptureTemplateKind.todo,
      titlePrefix: '买',
      tags: const ['生活'],
      priority: TodoPriority.medium,
      listGroupName: '购物',
    );

    final decoded = QuickCaptureTemplate.fromJson(original.toJson());

    expect(decoded.name, original.name);
    expect(decoded.kind, original.kind);
    expect(decoded.titlePrefix, original.titlePrefix);
    expect(decoded.tags, original.tags);
    expect(decoded.priority, original.priority);
    expect(decoded.listGroupName, original.listGroupName);
    expect(decoded.builtIn, isFalse);
  });
}
