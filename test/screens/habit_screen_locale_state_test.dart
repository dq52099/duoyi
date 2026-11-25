import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/habit.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/screens/habit_screen.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_support/recording_reminder_scheduler.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    I18n.setLocale(AppLocale.zh);
  });

  tearDown(() => I18n.setLocale(AppLocale.zh));

  for (final viewport in const [
    (width: 320.0, scale: 1.0),
    (width: 280.0, scale: 1.3),
    (width: 390.0, scale: 1.6),
  ]) {
    testWidgets(
      'open Habit add sheet retains locale and draft at ${viewport.width}px / ${viewport.scale}x',
      (tester) async {
        tester.view.physicalSize = Size(viewport.width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
        final scheduler = RecordingReminderScheduler();
        final timeAudit = TimeAuditProvider();
        final habits = HabitProvider()
          ..timeAudit = timeAudit
          ..scheduler = scheduler;
        final theme = ThemeProvider();
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          habits.dispose();
          timeAudit.dispose();
          theme.dispose();
        });

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<HabitProvider>.value(value: habits),
              ChangeNotifierProvider<TimeAuditProvider>.value(value: timeAudit),
              ChangeNotifierProvider<ThemeProvider>.value(value: theme),
            ],
            child: MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(viewport.scale)),
                child: child!,
              ),
              home: const HabitScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await tester.tap(find.byType(FloatingActionButton));
        await tester.pumpAndSettle();
        final form = find.byType(BottomSheet);
        expect(form, findsOneWidget);
        expect(
          find.descendant(of: form, matching: find.text('新建习惯')),
          findsOneWidget,
        );
        final observedLabels = <List<int>>[
          _formLocaleFingerprint(tester, form),
        ];

        final nameField = _field(tester, form, '习惯名称');
        final unitField = _field(tester, form, '单位');
        final categoryField = _field(tester, form, '分组');
        final targetField = _field(tester, form, '每日目标');

        await tester.ensureVisible(find.widgetWithText(TextField, '习惯名称'));
        await tester.enterText(
          find.widgetWithText(TextField, '习惯名称'),
          '晨间自定义习惯',
        );
        await tester.ensureVisible(find.widgetWithText(TextField, '单位'));
        await tester.enterText(find.widgetWithText(TextField, '单位'), 'ml');
        await tester.ensureVisible(find.widgetWithText(TextField, '分组'));
        await tester.enterText(find.widgetWithText(TextField, '分组'), '健康生活');
        await tester.ensureVisible(find.widgetWithText(TextField, '每日目标'));
        await tester.enterText(find.widgetWithText(TextField, '每日目标'), '3');

        final flexSwitch = find.descendant(
          of: form,
          matching: find.byType(Switch),
        );
        await tester.ensureVisible(flexSwitch);
        await tester.pumpAndSettle();
        expect(flexSwitch.hitTestable(), findsOneWidget);
        await tester.tap(flexSwitch);
        await tester.pumpAndSettle();

        final monthlyPeriod = find.descendant(
          of: form,
          matching: find.text(I18n.tr('habit.flex.monthly')),
        );
        await tester.ensureVisible(monthlyPeriod);
        await tester.pumpAndSettle();
        expect(monthlyPeriod.hitTestable(), findsOneWidget);
        await tester.tap(monthlyPeriod);
        await tester.pumpAndSettle();

        final flexTargetField = _field(
          tester,
          form,
          I18n.tr('habit.flex.period_target'),
        );
        await tester.ensureVisible(
          find.widgetWithText(TextField, I18n.tr('habit.flex.period_target')),
        );
        await tester.enterText(
          find.widgetWithText(TextField, I18n.tr('habit.flex.period_target')),
          '4',
        );
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        final addReminderTime = find.descendant(
          of: form,
          matching: find.text('添加时间'),
        );
        await tester.ensureVisible(addReminderTime);
        await tester.pumpAndSettle();
        expect(addReminderTime.hitTestable(), findsOneWidget);
        await tester.tap(addReminderTime);
        await tester.pumpAndSettle();
        final timePicker = find.byType(BottomSheet).last;
        final earlier = find.descendant(
          of: timePicker,
          matching: find.text(I18n.tr('picker.time.earlier_30m')),
        );
        await tester.ensureVisible(earlier);
        await tester.pumpAndSettle();
        expect(earlier.hitTestable(), findsOneWidget);
        await tester.tap(earlier);
        await tester.pumpAndSettle();
        final confirmTime = find.descendant(
          of: timePicker,
          matching: find.text(I18n.tr('action.confirm')),
        );
        await tester.ensureVisible(confirmTime);
        await tester.pumpAndSettle();
        expect(confirmTime.hitTestable(), findsOneWidget);
        await tester.tap(confirmTime);
        await tester.pumpAndSettle();

        final reminderTimesBeforeLocaleChanges = _reminderTimes(tester, form);
        expect(reminderTimesBeforeLocaleChanges, hasLength(2));

        await _pumpLocaleAndCheckLayout(tester, AppLocale.en);
        expect(form, findsOneWidget);
        expect(
          find.descendant(of: form, matching: find.text('New habit')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: form, matching: find.text('新建习惯')),
          findsNothing,
        );
        observedLabels.add(_formLocaleFingerprint(tester, form));

        await _pumpLocaleAndCheckLayout(tester, AppLocale.zh);
        expect(form, findsOneWidget);
        expect(
          find.descendant(of: form, matching: find.text('新建习惯')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: form, matching: find.text('New habit')),
          findsNothing,
        );
        observedLabels.add(_formLocaleFingerprint(tester, form));

        expect(
          observedLabels,
          const [
            [1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0],
            [0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1],
            [1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0],
          ],
          reason:
              'app-owned labels inside the open form must follow zh → en → zh',
        );

        expect(nameField.controller!.text, '晨间自定义习惯');
        expect(unitField.controller!.text, 'ml');
        expect(categoryField.controller!.text, '健康生活');
        expect(targetField.controller!.text, '3');
        expect(flexTargetField.controller!.text, '4');
        expect(
          tester
              .widget<SegmentedButton<HabitFlexPeriod>>(
                find.descendant(
                  of: form,
                  matching: find.byType(SegmentedButton<HabitFlexPeriod>),
                ),
              )
              .selected,
          {HabitFlexPeriod.month},
        );
        expect(
          tester
              .widget<Switch>(
                find.descendant(of: form, matching: find.byType(Switch)),
              )
              .value,
          isTrue,
        );
        expect(_reminderTimes(tester, form), reminderTimesBeforeLocaleChanges);
        expect(habits.habits, isEmpty);
        expect(scheduler.habitSyncs, isEmpty);
        expect(
          AccountLocalDataCleaner.accountDataGeneration,
          accountGeneration,
        );
        _expectNoFlutterExceptions(tester);
      },
    );
  }
}

void _expectNoFlutterExceptions(WidgetTester tester) {
  final exception = tester.takeException();
  expect(
    exception,
    isNull,
    reason: exception is FlutterError
        ? exception.diagnostics.map((node) => node.toStringDeep()).join('\n')
        : null,
  );
}

Future<void> _pumpLocaleAndCheckLayout(
  WidgetTester tester,
  AppLocale locale,
) async {
  final details = <FlutterErrorDetails>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (error) {
    details.add(error);
    previous?.call(error);
  };
  try {
    I18n.setLocale(locale);
    await tester.pumpAndSettle();
  } finally {
    FlutterError.onError = previous;
  }
  expect(
    tester.takeException(),
    isNull,
    reason: details.map((error) => error.toString()).join('\n'),
  );
}

TextField _field(WidgetTester tester, Finder scope, String label) {
  final finder = find.descendant(
    of: scope,
    matching: find.widgetWithText(TextField, label),
  );
  expect(finder, findsOneWidget, reason: 'expected one field labelled $label');
  return tester.widget<TextField>(finder);
}

List<int> _formLocaleFingerprint(WidgetTester tester, Finder form) {
  int count(String label) =>
      find.descendant(of: form, matching: find.text(label)).evaluate().length;

  return [
    count('习惯名称'),
    count('Habit name'),
    count('打卡提醒'),
    count('Check-in reminder'),
    count('目标规则'),
    count('Goal rules'),
    count('习惯周期'),
    count('Habit period'),
    count('生效星期'),
    count('Active weekdays'),
    count('单位'),
    count('Unit'),
  ];
}

List<String> _reminderTimes(WidgetTester tester, Finder form) => tester
    .widgetList<InputChip>(
      find.descendant(of: form, matching: find.byType(InputChip)),
    )
    .map((chip) => (chip.label as Text).data!)
    .toList();
