import 'dart:convert';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/reminder_editor_ui_copy.dart';
import 'package:duoyi/models/goal.dart';
import 'package:duoyi/models/recurrence.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/widgets/app_date_picker.dart';
import 'package:duoyi/widgets/recurrence_picker.dart';
import 'package:duoyi/widgets/reminder_plan_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppLocale originalLocale;

  setUp(() {
    originalLocale = I18n.current;
    I18n.setLocale(AppLocale.zh);
  });

  tearDown(() {
    I18n.setLocale(originalLocale);
  });

  testWidgets(
    'mounted plan rebuilds across locales and keeps supplied copy literal',
    (tester) async {
      const title = 'Literal reminder title / 保持原文';
      const subtitle = 'Never translate this subtitle — 原文';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReminderPlanEditor(
              plan: const ReminderPlan.disabled(),
              title: title,
              subtitle: subtitle,
              onChanged: (_) {},
            ),
          ),
        ),
      );
      expect(find.text(title), findsOneWidget);
      expect(find.text(subtitle), findsOneWidget);

      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      expect(find.text(title), findsOneWidget);
      expect(find.text(subtitle), findsOneWidget);

      I18n.setLocale(AppLocale.zh);
      await tester.pumpAndSettle();
      expect(find.text(title), findsOneWidget);
      expect(find.text(subtitle), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'plan summaries and recurrence labels localize without changing domain JSON',
    () {
      final oneRule = ReminderRule(id: 'one', type: ReminderRuleType.dailyTime);
      final twoRules = ReminderPlan(
        enabled: true,
        rules: [
          oneRule,
          ReminderRule(id: 'two', type: ReminderRuleType.weeklyTime),
        ],
      );
      const disabledPlan = ReminderPlan.disabled();
      final recurrence = RecurrenceRule(
        frequency: RecurrenceFrequency.weekly,
        interval: 2,
        byWeekdays: const [0, 2, 6],
        endDate: DateTime(2026, 11, 2),
        maxOccurrences: 3,
      );
      final oneOccurrence = RecurrenceRule(
        frequency: RecurrenceFrequency.daily,
        maxOccurrences: 1,
      );
      final rawRuleJson = jsonEncode(recurrence.toJson());
      final rawOneJson = jsonEncode(oneOccurrence.toJson());

      expect(reminderPlanSummary(disabledPlan), '已关闭');
      expect(reminderPlanSummary(twoRules), '2 条提醒');
      expect(ReminderEditorUiCopy.planSummaryCount(1), '1 条提醒');
      expect(ReminderEditorUiCopy.snoozeSummary(1), '稍后 1 分钟');
      expect(ReminderEditorUiCopy.repeatCountSummary(1), '重复 1 次');
      expect(recurrence.label, '每 2 周 · 一/三/日 · 至 2026年11月2日 · 共 3 次');
      expect(oneOccurrence.label, '每天 · 共 1 次');

      I18n.setLocale(AppLocale.en);
      expect(reminderPlanSummary(disabledPlan), 'Off');
      expect(reminderPlanSummary(twoRules), '2 reminders');
      expect(ReminderEditorUiCopy.planSummaryCount(1), '1 reminder');
      expect(ReminderEditorUiCopy.snoozeSummary(1), 'Snooze 1 min');
      expect(ReminderEditorUiCopy.repeatCountSummary(1), 'Repeat 1 time');
      expect(
        recurrence.label,
        'Every 2 weeks · Mon/Wed/Sun · Until Nov 2, 2026 · 3 times total',
      );
      expect(oneOccurrence.label, 'Daily · 1 time total');
      expect(jsonEncode(recurrence.toJson()), rawRuleJson);
      expect(jsonEncode(oneOccurrence.toJson()), rawOneJson);
    },
  );

  testWidgets('relative rule selections survive a zh/en rebuild and save', (
    tester,
  ) async {
    final initial = ReminderRule(
      id: 'relative-rule',
      type: ReminderRuleType.relativeToDue,
      kind: ReminderKind.alarm,
      hour: 21,
      minute: 35,
      offsetMinutes: -30,
      fullScreen: true,
      vibrate: false,
      snoozeMinutes: 5,
      repeatCount: 2,
    );
    ReminderPlan? changed;

    await _pumpEditor(tester, ReminderPlan(enabled: true, rules: [initial]), (
      value,
    ) {
      changed = value;
    });
    await _openRuleSheet(tester);

    I18n.setLocale(AppLocale.en);
    await tester.pumpAndSettle();
    expect(find.text(ReminderEditorUiCopy.reminderType), findsOneWidget);
    expect(find.text(ReminderEditorUiCopy.reminderMethod), findsOneWidget);
    expect(find.text('9:35 PM'), findsOneWidget);
    _expectSelectedChoiceChip(
      tester,
      ReminderEditorUiCopy.durationLabel(30),
      'reminder_relative_offset_presets',
    );
    _expectSelectedChoiceChip(
      tester,
      ReminderEditorUiCopy.snoozePresetLabel(5),
      'reminder_snooze_presets',
    );
    _expectSelectedChoiceChip(
      tester,
      ReminderEditorUiCopy.repeatCountPresetLabel(2),
      'reminder_repeat_count_presets',
    );
    expect(
      tester
          .widget<SegmentedButton<ReminderKind>>(
            find.byType(SegmentedButton<ReminderKind>),
          )
          .selected,
      <ReminderKind>{ReminderKind.alarm},
    );

    I18n.setLocale(AppLocale.zh);
    await tester.pumpAndSettle();
    expect(find.text(ReminderEditorUiCopy.reminderType), findsOneWidget);
    expect(find.text('21:35'), findsOneWidget);
    await _saveVisibleSheet(tester);

    final saved = changed!.rules.single;
    expect(saved.id, 'relative-rule');
    expect(saved.type, ReminderRuleType.relativeToDue);
    expect(saved.kind, ReminderKind.alarm);
    expect(saved.hour, 21);
    expect(saved.minute, 35);
    expect(saved.offsetMinutes, -30);
    expect(saved.fullScreen, isTrue);
    expect(saved.vibrate, isFalse);
    expect(saved.snoozeMinutes, 5);
    expect(saved.repeatCount, 2);
  });

  testWidgets('weekly rule weekdays survive an open-sheet locale rebuild', (
    tester,
  ) async {
    final initial = ReminderRule(
      id: 'weekly-rule',
      type: ReminderRuleType.weeklyTime,
      kind: ReminderKind.popup,
      hour: 6,
      minute: 45,
      weekdays: const [1, 3, 5],
      snoozeMinutes: 10,
      repeatCount: 1,
    );
    ReminderPlan? changed;

    await _pumpEditor(tester, ReminderPlan(enabled: true, rules: [initial]), (
      value,
    ) {
      changed = value;
    });
    await _openRuleSheet(tester);

    I18n.setLocale(AppLocale.en);
    await tester.pumpAndSettle();
    expect(find.text('6:45 AM'), findsOneWidget);
    for (final index in const [0, 2, 4]) {
      _expectSelectedFilterChip(
        tester,
        ReminderEditorUiCopy.weekdayNamesShort[index],
      );
    }
    expect(
      tester
          .widget<SegmentedButton<ReminderKind>>(
            find.byType(SegmentedButton<ReminderKind>),
          )
          .selected,
      <ReminderKind>{ReminderKind.popup},
    );

    I18n.setLocale(AppLocale.zh);
    await tester.pumpAndSettle();
    for (final index in const [0, 2, 4]) {
      _expectSelectedFilterChip(
        tester,
        ReminderEditorUiCopy.weekdayNamesShort[index],
      );
    }
    await _saveVisibleSheet(tester);

    final saved = changed!.rules.single;
    expect(saved.id, 'weekly-rule');
    expect(saved.type, ReminderRuleType.weeklyTime);
    expect(saved.kind, ReminderKind.popup);
    expect(saved.hour, 6);
    expect(saved.minute, 45);
    expect(saved.weekdays, const [1, 3, 5]);
    expect(saved.snoozeMinutes, 10);
    expect(saved.repeatCount, 1);
  });

  testWidgets(
    'recurrence fields, selected frequency, selection, and focus survive locale changes',
    (tester) async {
      final initial = RecurrenceRule(
        frequency: RecurrenceFrequency.monthly,
        interval: 3,
        byMonthDay: 17,
        endDate: DateTime(2027, 9, 30),
        maxOccurrences: 8,
      );
      final rawJson = jsonEncode(initial.toJson());
      RecurrenceRule? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await RecurrencePicker.show(
                    context,
                    initial: initial,
                  );
                },
                child: const Text('Open recurrence'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open recurrence'));
      await tester.pumpAndSettle();

      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(3));
      final controllers = fields
          .evaluate()
          .map((element) => (element.widget as TextField).controller!)
          .toList();
      expect(controllers.map((controller) => controller.text), [
        '3',
        '17',
        '8',
      ]);
      final intervalEditable = tester.widget<EditableText>(
        find.descendant(of: fields.at(0), matching: find.byType(EditableText)),
      );
      final intervalFocus = intervalEditable.focusNode;
      await tester.tap(fields.at(0));
      await tester.pump();
      controllers.first.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 1,
      );
      expect(intervalFocus.hasFocus, isTrue);

      for (final locale in [AppLocale.en, AppLocale.zh, AppLocale.en]) {
        I18n.setLocale(locale);
        await tester.pumpAndSettle();
        final frequencyChip = tester
            .widgetList<ChoiceChip>(find.byType(ChoiceChip))
            .singleWhere((chip) => chip.selected);
        expect(
          (frequencyChip.label as Text).data,
          ReminderEditorUiCopy.recurrenceFrequencyLabel(
            RecurrenceFrequency.monthly.index,
          ),
        );
        final rebuiltControllers = find
            .byType(TextField)
            .evaluate()
            .map((element) => (element.widget as TextField).controller!)
            .toList();
        expect(rebuiltControllers, hasLength(3));
        for (var index = 0; index < controllers.length; index++) {
          expect(rebuiltControllers[index], same(controllers[index]));
        }
        expect(controllers.map((controller) => controller.text), [
          '3',
          '17',
          '8',
        ]);
        expect(
          controllers.first.selection,
          const TextSelection(baseOffset: 0, extentOffset: 1),
        );
        expect(
          tester
              .widget<EditableText>(
                find.descendant(
                  of: find.byType(TextField).first,
                  matching: find.byType(EditableText),
                ),
              )
              .focusNode,
          same(intervalFocus),
        );
        expect(intervalFocus.hasFocus, isTrue);
        expect(jsonEncode(initial.toJson()), rawJson);
      }

      tester.binding.focusManager.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await _saveVisibleSheet(tester);
      expect(result?.frequency, RecurrenceFrequency.monthly);
      expect(result?.interval, 3);
      expect(result?.byMonthDay, 17);
      expect(result?.endDate, DateTime(2027, 9, 30));
      expect(result?.maxOccurrences, 8);
    },
  );

  testWidgets('open date picker heading and selected mode update with locale', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                AppDatePicker.show(
                  context,
                  initialDate: DateTime(2026, 5, 17),
                  firstDate: DateTime(2026, 1, 1),
                  lastDate: DateTime(2026, 12, 31),
                  initialMode: AppDatePickerMode.lunar,
                  titleKey: ReminderEditorUiCopy.datePickerTitleKey,
                );
              },
              child: const Text('Open date picker'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open date picker'));
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel(I18n.tr(ReminderEditorUiCopy.datePickerTitleKey)),
      findsOneWidget,
    );
    expect(
      tester
          .widget<SegmentedButton<AppDatePickerMode>>(
            find.byType(SegmentedButton<AppDatePickerMode>),
          )
          .selected,
      <AppDatePickerMode>{AppDatePickerMode.lunar},
    );

    I18n.setLocale(AppLocale.en);
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel(I18n.tr(ReminderEditorUiCopy.datePickerTitleKey)),
      findsOneWidget,
    );
    expect(
      tester
          .widget<SegmentedButton<AppDatePickerMode>>(
            find.byType(SegmentedButton<AppDatePickerMode>),
          )
          .selected,
      <AppDatePickerMode>{AppDatePickerMode.lunar},
    );
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'account change leaves a nested picker on top and blocks recurrence result',
    (tester) async {
      final initial = RecurrenceRule(frequency: RecurrenceFrequency.monthly);
      RecurrenceRule? result;
      var completed = false;
      final navigatorKey = GlobalKey<NavigatorState>();

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await RecurrencePicker.show(
                    context,
                    initial: initial,
                  );
                  completed = true;
                },
                child: const Text('Open account-scoped recurrence'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open account-scoped recurrence'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(ReminderEditorUiCopy.endDateNever));
      await tester.pumpAndSettle();

      AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel(I18n.tr(ReminderEditorUiCopy.datePickerTitleKey)),
        findsOneWidget,
        reason: 'the recurrence listener must not pop the date picker above it',
      );
      expect(tester.takeException(), isNull);

      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(
        find.byType(RecurrencePicker),
        findsNothing,
        reason:
            'the invalid owned sheet dismisses once its nested picker closes',
      );
      expect(completed, isTrue);
      expect(result, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'account change before a reminder rule save yields no onChanged',
    (tester) async {
      var changedCount = 0;
      final plan = ReminderPlan(
        enabled: true,
        rules: [
          ReminderRule(id: 'stale-rule', type: ReminderRuleType.dailyTime),
        ],
      );
      await _pumpEditor(tester, plan, (_) => changedCount++);
      await _openRuleSheet(tester);

      AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      await tester.pumpAndSettle();
      expect(changedCount, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('removing the original plan caller prevents a late onChanged', (
    tester,
  ) async {
    var showEditor = true;
    var changedCount = 0;
    late StateSetter setPageState;
    final plan = ReminderPlan(
      enabled: true,
      rules: [
        ReminderRule(id: 'removed-caller', type: ReminderRuleType.dailyTime),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            setPageState = setState;
            return Scaffold(
              body: showEditor
                  ? ReminderPlanEditor(
                      plan: plan,
                      onChanged: (_) => changedCount++,
                    )
                  : const Text('Caller removed'),
            );
          },
        ),
      ),
    );
    await _openRuleSheet(tester);
    setPageState(() => showEditor = false);
    await tester.pumpAndSettle();
    expect(find.text('Caller removed'), findsOneWidget);

    await _saveVisibleSheet(tester);
    expect(changedCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a stale surviving rule sheet cannot open its type route or apply a draft',
    (tester) async {
      var showEditor = true;
      var changedCount = 0;
      late StateSetter setPageState;
      final observer = _RecordingNavigatorObserver();
      final plan = ReminderPlan(
        enabled: true,
        rules: [
          ReminderRule(
            id: 'stale-type-menu',
            type: ReminderRuleType.dailyTime,
            hour: 9,
            minute: 15,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [observer],
          home: StatefulBuilder(
            builder: (context, setState) {
              setPageState = setState;
              return Scaffold(
                body: showEditor
                    ? ReminderPlanEditor(
                        plan: plan,
                        onChanged: (_) => changedCount++,
                      )
                    : const Text('Original editor removed'),
              );
            },
          ),
        ),
      );
      await _openRuleSheet(tester);
      expect(observer.pushed, isNotEmpty);
      final ownedSheetRoute = observer.pushed.last;
      expect(ownedSheetRoute.isCurrent, isTrue);

      setPageState(() => showEditor = false);
      await tester.pumpAndSettle();
      expect(find.text('Original editor removed'), findsOneWidget);
      expect(ownedSheetRoute.isCurrent, isTrue);

      final currentType = ReminderEditorUiCopy.ruleTypeLabelByName(
        ReminderRuleType.dailyTime.name,
      );
      expect(find.text(currentType), findsOneWidget);
      final pushesBeforeTypeTap = observer.pushed.length;
      await tester.tap(find.text(currentType));
      await tester.pumpAndSettle();

      expect(
        observer.pushed.length,
        pushesBeforeTypeTap,
        reason: 'no anchored type menu may be pushed from a removed caller',
      );
      expect(changedCount, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'an open type menu relocalizes without changing its selected enum',
    (tester) async {
      final observer = _RecordingNavigatorObserver();
      final navigatorKey = GlobalKey<NavigatorState>();
      final initial = ReminderRule(
        id: 'open-type-menu',
        type: ReminderRuleType.dailyTime,
        kind: ReminderKind.popup,
        hour: 10,
        minute: 20,
      );
      final changed = <ReminderPlan>[];

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          navigatorObservers: [observer],
          home: Scaffold(
            body: ReminderPlanEditor(
              plan: ReminderPlan(enabled: true, rules: [initial]),
              onChanged: changed.add,
            ),
          ),
        ),
      );
      await _openRuleSheet(tester);
      final sheetRoute = observer.pushed.last;
      final currentType = ReminderEditorUiCopy.ruleTypeLabelByName(
        ReminderRuleType.dailyTime.name,
      );
      final pushesBeforeMenu = observer.pushed.length;
      await tester.tap(find.text(currentType));
      await tester.pumpAndSettle();

      expect(observer.pushed.length, pushesBeforeMenu + 1);
      final menuRoute = observer.pushed.last;
      expect(menuRoute, isNot(same(sheetRoute)));
      expect(menuRoute.isCurrent, isTrue);
      final zhAlternative = ReminderEditorUiCopy.ruleTypeLabelByName(
        ReminderRuleType.absolute.name,
      );
      expect(find.text(zhAlternative), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);

      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      final enAlternative = ReminderEditorUiCopy.ruleTypeLabelByName(
        ReminderRuleType.absolute.name,
      );
      expect(find.text(enAlternative), findsOneWidget);
      expect(find.text(zhAlternative), findsNothing);
      expect(observer.pushed.length, pushesBeforeMenu + 1);
      expect(observer.pushed.last, same(menuRoute));
      expect(menuRoute.isCurrent, isTrue);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);

      I18n.setLocale(AppLocale.zh);
      await tester.pumpAndSettle();
      expect(find.text(zhAlternative), findsOneWidget);
      expect(observer.pushed.last, same(menuRoute));
      expect(menuRoute.isCurrent, isTrue);

      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(sheetRoute.isCurrent, isTrue);
      await _saveVisibleSheet(tester);
      expect(changed, hasLength(1));
      expect(changed.single.rules.single.type, ReminderRuleType.dailyTime);
      expect(changed.single.rules.single.kind, ReminderKind.popup);
    },
  );

  testWidgets(
    'clear end date tooltip relocalizes and preserves other recurrence fields',
    (tester) async {
      final initial = RecurrenceRule(
        frequency: RecurrenceFrequency.monthly,
        interval: 3,
        byMonthDay: 17,
        endDate: DateTime(2027, 9, 30),
        maxOccurrences: 8,
      );
      final rawJson = jsonEncode(initial.toJson());
      RecurrenceRule? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await RecurrencePicker.show(
                    context,
                    initial: initial,
                  );
                },
                child: const Text('Open end-date recurrence'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open end-date recurrence'));
      await tester.pumpAndSettle();

      final zhTooltip = ReminderEditorUiCopy.clearEndDateTooltip;
      expect(find.byTooltip(zhTooltip), findsOneWidget);
      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      final enTooltip = ReminderEditorUiCopy.clearEndDateTooltip;
      expect(enTooltip, isNot(zhTooltip));
      expect(find.byTooltip(enTooltip), findsOneWidget);
      I18n.setLocale(AppLocale.zh);
      await tester.pumpAndSettle();
      expect(
        find.byTooltip(ReminderEditorUiCopy.clearEndDateTooltip),
        findsOneWidget,
      );

      await tester.tap(
        find.byTooltip(ReminderEditorUiCopy.clearEndDateTooltip),
      );
      await tester.pumpAndSettle();
      expect(
        find.byTooltip(ReminderEditorUiCopy.clearEndDateTooltip),
        findsNothing,
      );
      expect(find.text(ReminderEditorUiCopy.endDateNever), findsOneWidget);
      expect(jsonEncode(initial.toJson()), rawJson);

      await _saveVisibleSheet(tester);
      expect(result, isNotNull);
      expect(result!.frequency, RecurrenceFrequency.monthly);
      expect(result!.interval, 3);
      expect(result!.byMonthDay, 17);
      expect(result!.endDate, isNull);
      expect(result!.maxOccurrences, 8);
      expect(jsonEncode(initial.toJson()), rawJson);
    },
  );

  testWidgets(
    'removing the recurrence caller turns its late result into null',
    (tester) async {
      var showCaller = true;
      var completed = false;
      RecurrenceRule? result;
      late StateSetter setPageState;
      final initial = RecurrenceRule(frequency: RecurrenceFrequency.daily);

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (pageContext, setState) {
              setPageState = setState;
              return Scaffold(
                body: showCaller
                    ? Builder(
                        builder: (callerContext) => TextButton(
                          onPressed: () async {
                            result = await RecurrencePicker.show(
                              callerContext,
                              initial: initial,
                            );
                            completed = true;
                          },
                          child: const Text('Open removable recurrence caller'),
                        ),
                      )
                    : const Text('Recurrence caller removed'),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('Open removable recurrence caller'));
      await tester.pumpAndSettle();
      setPageState(() => showCaller = false);
      await tester.pumpAndSettle();
      expect(find.text('Recurrence caller removed'), findsOneWidget);

      await _saveVisibleSheet(tester);
      await tester.pumpAndSettle();
      expect(completed, isTrue);
      expect(result, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reverse dismissal releases picker controllers and locale listeners',
    (tester) async {
      final accountNotifier =
          AccountLocalDataCleaner.accountDataGenerationListenable
              as ChangeNotifier;
      final accountListenersBefore = _hasNotifierListeners(accountNotifier);
      final localeListenersBefore = _hasNotifierListeners(
        I18n.localeListenable,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  await RecurrencePicker.show(
                    context,
                    initial: RecurrenceRule(
                      frequency: RecurrenceFrequency.monthly,
                      interval: 2,
                      byMonthDay: 12,
                      maxOccurrences: 4,
                    ),
                  );
                },
                child: const Text('Open disposable picker'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open disposable picker'));
      await tester.pumpAndSettle();
      final controllers = find
          .byType(TextField)
          .evaluate()
          .map((element) => (element.widget as TextField).controller!)
          .toList();
      expect(_hasNotifierListeners(accountNotifier), isTrue);
      expect(_hasNotifierListeners(I18n.localeListenable), isTrue);

      await tester.tap(find.text(ReminderEditorUiCopy.cancel));
      await tester.pumpAndSettle();
      expect(find.byType(RecurrencePicker), findsNothing);
      expect(controllers.map(_hasNotifierListeners), everyElement(isFalse));
      expect(_hasNotifierListeners(accountNotifier), accountListenersBefore);
      expect(
        _hasNotifierListeners(I18n.localeListenable),
        localeListenersBefore,
      );

      I18n.setLocale(AppLocale.en);
      AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('320-wide enlarged text keeps the open reminder sheet usable', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final plan = ReminderPlan(
      enabled: true,
      rules: [
        ReminderRule(
          id: 'large-type',
          type: ReminderRuleType.weeklyTime,
          kind: ReminderKind.alarm,
          hour: 8,
          minute: 15,
          weekdays: const [1, 3, 5],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(1.4)),
            child: Scaffold(
              body: ReminderPlanEditor(plan: plan, onChanged: (_) {}),
            ),
          ),
        ),
      ),
    );
    await _openRuleSheet(tester);
    I18n.setLocale(AppLocale.en);
    await tester.pumpAndSettle();

    expect(find.byType(SingleChildScrollView), findsWidgets);
    expect(find.text(ReminderEditorUiCopy.save), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpEditor(
  WidgetTester tester,
  ReminderPlan plan,
  ValueChanged<ReminderPlan> onChanged,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ReminderPlanEditor(plan: plan, onChanged: onChanged),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openRuleSheet(WidgetTester tester) async {
  await tester.tap(find.byType(ListTile).first);
  await tester.pumpAndSettle();
  expect(find.text(ReminderEditorUiCopy.save), findsOneWidget);
}

Future<void> _saveVisibleSheet(WidgetTester tester) async {
  final save = find.text(ReminderEditorUiCopy.save);
  expect(save, findsOneWidget);
  await tester.ensureVisible(save);
  await tester.tap(save);
  await tester.pumpAndSettle();
}

void _expectSelectedChoiceChip(
  WidgetTester tester,
  String label,
  String groupKey,
) {
  final chip = find.ancestor(
    of: find.descendant(
      of: find.byKey(ValueKey(groupKey)),
      matching: find.text(label),
    ),
    matching: find.byType(ChoiceChip),
  );
  expect(chip, findsOneWidget, reason: label);
  expect(tester.widget<ChoiceChip>(chip).selected, isTrue, reason: label);
}

void _expectSelectedFilterChip(WidgetTester tester, String label) {
  final chip = find.ancestor(
    of: find.text(label),
    matching: find.byType(FilterChip),
  );
  expect(chip, findsOneWidget, reason: label);
  expect(tester.widget<FilterChip>(chip).selected, isTrue, reason: label);
}

class _RecordingNavigatorObserver extends NavigatorObserver {
  final List<Route<dynamic>> pushed = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
    super.didPush(route, previousRoute);
  }
}

// Listener cleanup is part of this fixture's explicit resource contract.
// Reading the protected diagnostic avoids removing those assertions.
bool _hasNotifierListeners(ChangeNotifier notifier) {
  // ignore: invalid_use_of_protected_member
  return notifier.hasListeners;
}
