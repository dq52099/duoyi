import 'package:duoyi/models/goal.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_support/recording_reminder_scheduler.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'goal writes sync reminders immediately when scheduler is injected',
    () async {
      final scheduler = RecordingReminderScheduler();
      final provider = GoalProvider()..scheduler = scheduler;
      final goal = GoalItem(
        id: 'goal-sync',
        title: '读完一本书',
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'rule',
              type: ReminderRuleType.dailyTime,
              kind: ReminderKind.push,
              hour: 9,
              minute: 0,
            ),
          ],
        ),
      );

      await provider.add(goal);
      expect(scheduler.goalSyncs, [
        ['goal-sync'],
      ]);

      await provider.update(
        GoalItem(id: goal.id, title: '读完两本书', reminderPlan: goal.reminderPlan),
      );
      expect(scheduler.goalSyncs, [
        ['goal-sync'],
        ['goal-sync'],
      ]);

      await provider.delete(goal.id);
      expect(scheduler.goalSyncs.last, isEmpty);
    },
  );
}
