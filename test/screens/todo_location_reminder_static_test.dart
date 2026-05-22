import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'Todo detail can create location reminders linked to the current task',
    () {
      final source = File(
        'lib/screens/todo_detail_screen.dart',
      ).readAsStringSync();

      expect(source, contains("import '../models/location_reminder.dart';"));
      expect(
        source,
        contains("import '../providers/location_reminder_provider.dart';"),
      );
      expect(source, contains('context.watch<LocationReminderProvider?>()'));
      expect(source, contains('_TodoLocationReminderCard'));
      expect(source, contains('_addLinkedLocationReminder('));
      expect(source, contains("linkedType: 'todo'"));
      expect(source, contains('linkedId: _todo.id'));
      expect(source, contains('oneShot: oneShot'));
      expect(source, contains('LocationTrigger.enter'));
      expect(source, contains('LocationTrigger.leave'));
      expect(source, contains('provider.add('));
      expect(source, contains("content: Text('已添加任务位置提醒')"));
    },
  );

  test('location notification payload opens linked todo when available', () {
    final source = File(
      'lib/providers/notification_service.dart',
    ).readAsStringSync();

    expect(source, contains("if (reminder.linkedType == 'todo')"));
    expect(source, contains("return 'duoyi://todo/\$linkedId'"));
    expect(source, contains("return 'duoyi://location/"));
  });
}
