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

  testWidgets('ReminderPlanEditor 隐藏提醒方式时仍使用 defaultKind', (tester) async {
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
            defaultKind: ReminderKind.alarm,
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
    expect(plan.rules.single.kind, ReminderKind.alarm);
    expect(plan.rules.single.fullScreen, isFalse);
  });

  testWidgets('ReminderPlanEditor 允许闹钟时默认全屏提醒', (tester) async {
    var plan = const ReminderPlan.disabled();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReminderPlanEditor(
            plan: plan,
            maxRules: 1,
            allowAlarm: true,
            allowRelativeToDue: false,
            hasAnchorDate: false,
            defaultKind: ReminderKind.alarm,
            onChanged: (next) => plan = next,
          ),
        ),
      ),
    );

    await tester.tap(find.text('提醒'));
    await tester.pump();

    expect(plan.enabled, isTrue);
    expect(plan.rules, hasLength(1));
    expect(plan.rules.single.kind, ReminderKind.alarm);
    expect(plan.rules.single.fullScreen, isTrue);
  });

  testWidgets(
    'ReminderPlanEditor exposes notification popup alarm and can turn off',
    (tester) async {
      var plan = const ReminderPlan.disabled();

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) => Scaffold(
              body: ReminderPlanEditor(
                plan: plan,
                maxRules: 1,
                allowAlarm: true,
                allowRelativeToDue: false,
                hasAnchorDate: false,
                onChanged: (next) => setState(() => plan = next),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('提醒'));
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('每日提醒'));
      await tester.pumpAndSettle();

      expect(find.text('提醒方式'), findsOneWidget);
      expect(find.text('通知'), findsOneWidget);
      expect(find.text('弹出框'), findsOneWidget);
      expect(find.text('闹钟'), findsOneWidget);
      expect(find.text('关闭'), findsWidgets);

      await tester.tap(find.text('弹出框'));
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(plan.enabled, isTrue);
      expect(plan.rules.single.kind, ReminderKind.popup);

      await tester.tap(find.text('每日提醒 · 弹出框'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.notifications_off_outlined));
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(plan.enabled, isTrue);
      expect(plan.rules.single.kind, ReminderKind.off);
      expect(plan.rules.single.enabled, isFalse);
    },
  );

  testWidgets('ReminderPlanEditor normalizes legacy email to notification', (
    tester,
  ) async {
    var plan = ReminderPlan(
      enabled: true,
      rules: [
        ReminderRule(
          id: 'legacy-email',
          enabled: true,
          type: ReminderRuleType.dailyTime,
          kind: ReminderKind.email,
          hour: 9,
          minute: 0,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: ReminderPlanEditor(
              plan: plan,
              maxRules: 1,
              allowAlarm: true,
              allowRelativeToDue: false,
              hasAnchorDate: false,
              onChanged: (next) => setState(() => plan = next),
            ),
          ),
        ),
      ),
    );

    expect(find.text('每日提醒 · 通知'), findsOneWidget);
    expect(find.text('每日提醒 · 邮件'), findsNothing);

    await tester.tap(find.text('每日提醒 · 通知'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final segmented = tester.widget<SegmentedButton<ReminderKind>>(
      find.byType(SegmentedButton<ReminderKind>),
    );
    expect(segmented.selected, <ReminderKind>{ReminderKind.push});
    expect(
      segmented.segments.map((segment) => segment.value).toList(),
      <ReminderKind>[
        ReminderKind.push,
        ReminderKind.popup,
        ReminderKind.alarm,
        ReminderKind.off,
      ],
    );

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(plan.rules.single.kind, ReminderKind.push);
  });

  testWidgets('ReminderPlanEditor selected controls use readable text colors', (
    tester,
  ) async {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.teal);
    var plan = const ReminderPlan.disabled();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorScheme: scheme),
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: ReminderPlanEditor(
              plan: plan,
              maxRules: 1,
              allowAlarm: true,
              allowRelativeToDue: false,
              hasAnchorDate: false,
              onChanged: (next) => setState(() => plan = next),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('提醒'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('每日提醒'));
    await tester.pumpAndSettle();

    final segmented = tester.widget<SegmentedButton<ReminderKind>>(
      find.byType(SegmentedButton<ReminderKind>),
    );
    final expectedSelectedBackground = Color.alphaBlend(
      scheme.primary.withValues(alpha: 0.09),
      scheme.surface,
    );
    final expectedSelectedForeground = _readableForeground(
      expectedSelectedBackground,
      scheme.onSurface,
    );
    expect(
      segmented.style?.backgroundColor?.resolve({WidgetState.selected}),
      expectedSelectedBackground,
    );
    expect(
      segmented.style?.foregroundColor?.resolve({WidgetState.selected}),
      expectedSelectedForeground,
    );
    expect(
      segmented.style?.iconColor?.resolve({WidgetState.selected}),
      expectedSelectedForeground,
    );

    final selectedChips = tester
        .widgetList<ChoiceChip>(
          find.byWidgetPredicate(
            (widget) => widget is ChoiceChip && widget.selected,
          ),
        )
        .toList();
    expect(selectedChips, isNotEmpty);
    for (final chip in selectedChips) {
      expect(chip.selectedColor, expectedSelectedBackground);
      expect(chip.checkmarkColor, expectedSelectedForeground);
      expect(chip.labelStyle?.color, expectedSelectedForeground);
    }
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

Color _readableForeground(Color background, Color preferred) {
  final preferredContrast = _contrastRatio(background, preferred);
  final blackContrast = _contrastRatio(background, Colors.black);
  final whiteContrast = _contrastRatio(background, Colors.white);
  if (preferredContrast >= 4.5 ||
      (preferredContrast >= blackContrast &&
          preferredContrast >= whiteContrast)) {
    return preferred;
  }
  return blackContrast >= whiteContrast ? Colors.black : Colors.white;
}

double _contrastRatio(Color a, Color b) {
  final l1 = a.computeLuminance() + 0.05;
  final l2 = b.computeLuminance() + 0.05;
  return l1 > l2 ? l1 / l2 : l2 / l1;
}
