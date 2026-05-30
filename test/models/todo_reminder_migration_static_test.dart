import 'package:duoyi/models/goal.dart';
import 'package:duoyi/models/todo.dart';
import 'package:test/test.dart';

void main() {
  test('enabled legacy reminder survives stale disabled reminderPlan', () {
    final today = DateTime(2026, 5, 25, 0, 0).toIso8601String();
    final todo = TodoItem.fromJson(<String, dynamic>{
      'id': 'stale-plan-reminder',
      'title': '三点四十提醒',
      'quadrant': 1,
      'priority': 0,
      'date': today,
      'dueDate': DateTime(2026, 5, 25, 15, 40).toIso8601String(),
      'createdAt': today,
      'updatedAt': today,
      'hasReminder': true,
      'reminderAt': DateTime(2026, 5, 25, 15, 40).toIso8601String(),
      'reminder': <String, dynamic>{
        'enabled': true,
        'kind': ReminderKind.push.index,
        'hour': 15,
        'minute': 40,
      },
      'reminderPlan': <String, dynamic>{
        'enabled': false,
        'rules': [
          <String, dynamic>{
            'id': 'stale-rule',
            'enabled': true,
            'type': ReminderRuleType.absolute.index,
            'kind': ReminderKind.push.index,
            'hour': 15,
            'minute': 40,
          },
        ],
      },
    });

    expect(todo.reminder.enabled, isTrue);
    expect(todo.reminder.hour, 15);
    expect(todo.reminder.minute, 40);
    expect(todo.reminderPlan.enabled, isTrue);
    expect(todo.reminderPlan.primaryRule?.hour, 15);
    expect(todo.reminderPlan.primaryRule?.minute, 40);
  });
}
