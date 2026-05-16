import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:duoyi/models/goal.dart';
import 'package:duoyi/widgets/reminder_plan_editor.dart';

void main() {
  testWidgets('ReminderPlanEditor 开启时补入默认 rule', (tester) async {
    var plan = const ReminderPlan.disabled();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReminderPlanEditor(
            plan: plan,
            maxRules: 1,
            allowAlarm: false,
            allowRelativeToDue: false,
            hasAnchorDate: false,
            onChanged: (next) => plan = next,
          ),
        ),
      ),
    );

    await tester.tap(find.text('提醒'));
    await tester.pump();

    expect(plan.enabled, isTrue);
    expect(plan.rules, hasLength(1));
    expect(plan.rules.single.type, ReminderRuleType.dailyTime);
    expect(plan.rules.single.kind, ReminderKind.push);
  });

  test('nextHalfHourTimeOfDay 使用向后最近半小时点', () {
    expect(
      nextHalfHourTimeOfDay(DateTime(2026, 5, 13, 17, 28)),
      const TimeOfDay(hour: 17, minute: 30),
    );
    expect(
      nextHalfHourTimeOfDay(DateTime(2026, 5, 13, 17, 35)),
      const TimeOfDay(hour: 18, minute: 0),
    );
  });
}
