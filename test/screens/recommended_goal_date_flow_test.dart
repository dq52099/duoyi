import 'dart:async';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/goal_validation.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/i18n_date_format.dart';
import 'package:duoyi/core/recommended_goals_ui_copy.dart';
import 'package:duoyi/models/goal.dart';
import 'package:duoyi/providers/app_lock_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/screens/recommended_goals_picker.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/services/app_access_route_gate.dart';
import 'package:duoyi/services/app_update_service.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    I18n.setLocale(AppLocale.zh);
  });

  tearDown(() => I18n.setLocale(AppLocale.zh));

  testWidgets(
    'Explicit future date selection confirms and persists exactly once with 3-day advance reminder and valid goal',
    (tester) async {
      final fixture = await _mountPicker(tester);
      await _openPicker(tester);
      await _switchToHealth(tester);

      await _tapAnnualCheckup(tester);
      final chosenDate = await _selectExplicitFutureDate(tester);
      await _confirmDate(tester);
      await _drainWrites(tester);

      expect(fixture.store.goalWriteAttempts, 1);
      expect(fixture.goals.goals, hasLength(1));

      final savedGoal = fixture.goals.goals.first;
      expect(savedGoal.title, isNotEmpty);
      expect(savedGoal.category, GoalCategory.health);
      expect(savedGoal.targetDate, isNotNull);
      expect(
        DateUtils.isSameDay(savedGoal.targetDate, chosenDate),
        isTrue,
        reason: 'Target date must match the chosen future date',
      );
      expect(savedGoal.reminder.enabled, isTrue);
      expect(savedGoal.reminder.daysBefore, 3);
      expect(isGoalValid(savedGoal), isTrue);
      expect(
        find.byKey(const ValueKey('recommended-goal-view')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Cancel in date picker performs zero writes and leaves goals empty',
    (tester) async {
      final fixture = await _mountPicker(tester);
      await _openPicker(tester);
      await _switchToHealth(tester);

      await _tapAnnualCheckup(tester);
      expect(
        find.widgetWithText(TextButton, I18n.tr('action.cancel')),
        findsOneWidget,
      );

      await _cancelDate(tester);

      expect(fixture.store.goalWriteAttempts, 0);
      expect(fixture.goals.goals, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byKey(const ValueKey('recommended-goal-view')), findsNothing);
      expect(find.byType(RecommendedGoalsPicker), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Confirming default selected date when date picker opens persists targetDate and passes validation',
    (tester) async {
      final fixture = await _mountPicker(tester);
      await _openPicker(tester);
      await _switchToHealth(tester);

      await _tapAnnualCheckup(tester);
      await _confirmDate(tester);
      await _drainWrites(tester);

      expect(fixture.store.goalWriteAttempts, 1);
      expect(fixture.goals.goals, hasLength(1));

      final savedGoal = fixture.goals.goals.first;
      expect(savedGoal.targetDate, isNotNull);
      expect(savedGoal.reminder.enabled, isTrue);
      expect(savedGoal.reminder.daysBefore, 3);
      expect(isGoalValid(savedGoal), isTrue);
      expect(
        find.byKey(const ValueKey('recommended-goal-view')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Queued activation callback regression while date sheet is open or write is held does not double-create goal',
    (tester) async {
      final fixture = await _mountPicker(tester);
      await _openPicker(tester);
      await _switchToHealth(tester);

      final addFinder = _addButton('rec.health.annual_checkup');
      await tester.scrollUntilVisible(
        addFinder,
        100,
        scrollable: find.descendant(
          of: _goalList('health'),
          matching: find.byType(Scrollable),
        ),
      );
      final initialButton = tester.widget<IconButton>(addFinder);
      expect(initialButton.onPressed, isNotNull);
      final queuedActivationCallback = initialButton.onPressed!;

      await tester.tap(addFinder);
      await _waitForModalSheet(tester);
      expect(find.byType(AppModalSheet), findsOneWidget);

      // Verify product _pending guard against queued activation callback regression
      // (e.g. stale-frame or queued gesture dispatch) while the date sheet is open.
      queuedActivationCallback();
      await tester.pump();
      expect(find.byType(AppModalSheet), findsOneWidget);
      expect(fixture.store.goalWriteAttempts, 0);

      final chosenDate = await _selectExplicitFutureDate(tester);

      fixture.store.armHold();
      await _confirmDate(tester);
      await _waitForHeldWrite(tester, fixture.store);

      expect(fixture.store.goalWriteAttempts, 1);
      final button = tester.widget<IconButton>(addFinder);
      expect(button.onPressed, isNull);

      await tester.tap(addFinder);
      queuedActivationCallback();
      await tester.pump();
      expect(fixture.store.goalWriteAttempts, 1);

      await _releaseHeldWrite(tester, fixture);

      expect(fixture.store.goalWriteAttempts, 1);
      expect(fixture.goals.goals, hasLength(1));
      final savedGoal = fixture.goals.goals.first;
      expect(DateUtils.isSameDay(savedGoal.targetDate, chosenDate), isTrue);
      expect(isGoalValid(savedGoal), isTrue);
      expect(
        find.byKey(const ValueKey('recommended-goal-view')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Template without target date requirement applies directly without opening date sheet',
    (tester) async {
      final fixture = await _mountPicker(tester);
      await _openPicker(tester);

      final addFinder = _addButton('rec.recommend.drink_water');
      expect(addFinder, findsOneWidget);
      await tester.tap(addFinder);
      await _drainWrites(tester);

      expect(find.byType(AppModalSheet), findsNothing);
      expect(
        find.widgetWithText(FilledButton, I18n.tr('action.confirm')),
        findsNothing,
      );

      expect(fixture.store.goalWriteAttempts, 1);
      expect(fixture.goals.goals, hasLength(1));
      final savedGoal = fixture.goals.goals.first;
      expect(savedGoal.targetDate, isNull);
      expect(savedGoal.reminder.daysBefore, 0);
      expect(isGoalValid(savedGoal), isTrue);
      expect(
        find.byKey(const ValueKey('recommended-goal-view')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Health template without advance reminder applies directly without date sheet',
    (tester) async {
      final fixture = await _mountPicker(tester);
      await _openPicker(tester);
      await _switchToHealth(tester);

      final addFinder = _addButton('rec.health.water_8_glasses');
      await tester.scrollUntilVisible(
        addFinder,
        100,
        scrollable: find.descendant(
          of: _goalList('health'),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(addFinder);
      await _drainWrites(tester);

      expect(find.byType(AppModalSheet), findsNothing);
      expect(
        find.widgetWithText(FilledButton, I18n.tr('action.confirm')),
        findsNothing,
      );
      expect(fixture.store.goalWriteAttempts, 1);
      expect(fixture.goals.goals, hasLength(1));
      expect(fixture.goals.goals.first.targetDate, isNull);
      expect(isGoalValid(fixture.goals.goals.first), isTrue);
      expect(
        find.byKey(const ValueKey('recommended-goal-view')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Locale change while date sheet is showing preserves category, selected date, and sheet state',
    (tester) async {
      final fixture = await _mountPicker(tester, initialLocale: AppLocale.zh);
      await _openPicker(tester);
      await _switchToHealth(tester);

      await _tapAnnualCheckup(tester);
      expect(
        find.descendant(
          of: find.byType(AppModalSheet),
          matching: find.text('年度体检提醒'),
        ),
        findsOneWidget,
      );
      expect(
        find.text(RecommendedGoalsUiCopy.selectTargetDate),
        findsOneWidget,
      );
      expect(find.widgetWithText(FilledButton, '确定'), findsOneWidget);
      expect(find.widgetWithText(TextButton, '取消'), findsOneWidget);

      final chosenDate = await _selectExplicitFutureDate(tester);

      I18n.setLocale(AppLocale.en);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        if (find.widgetWithText(FilledButton, 'OK').evaluate().isNotEmpty) {
          break;
        }
      }

      expect(
        find.descendant(
          of: find.byType(AppModalSheet),
          matching: find.text('Annual health checkup'),
        ),
        findsOneWidget,
      );
      expect(find.text('Select target date'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'OK'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);

      final healthChip = tester.widget<ChoiceChip>(_category('health'));
      expect(healthChip.selected, isTrue);
      expect((healthChip.label as Text).data, 'Health');

      await tester.tap(find.widgetWithText(FilledButton, 'OK'));
      await _pumpFrames(tester, count: 15);
      await _drainWrites(tester);

      expect(fixture.store.goalWriteAttempts, 1);
      expect(fixture.goals.goals, hasLength(1));
      final savedGoal = fixture.goals.goals.first;
      expect(DateUtils.isSameDay(savedGoal.targetDate, chosenDate), isTrue);
      expect(savedGoal.reminder.daysBefore, 3);
      expect(isGoalValid(savedGoal), isTrue);
      expect(find.text('Added to your goals'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Same-frame route cover and return while date sheet is open proactively dismisses date sheet and prevents writes',
    (tester) async {
      final fixture = await _mountPicker(tester);
      await _openPicker(tester);
      await _switchToHealth(tester);

      await _tapAnnualCheckup(tester);
      await _selectExplicitFutureDate(tester);

      final revision = fixture.routeGate.routeRevision.value;
      final navigator = fixture.navigator.currentState!;
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Cover Route')),
          ),
        ),
      );
      navigator.pop();
      expect(fixture.routeGate.routeRevision.value, revision + 2);
      await _pumpFrames(tester, count: 10);

      final confirmFinder = find.widgetWithText(
        FilledButton,
        I18n.tr('action.confirm'),
      );
      if (confirmFinder.evaluate().isNotEmpty) {
        await tester.tap(confirmFinder);
        await _pumpFrames(tester, count: 15);
      } else {
        expect(
          find.byType(AppModalSheet),
          findsNothing,
          reason:
              'Owned date sheet was proactively removed by route invalidation',
        );
      }
      await _drainWrites(tester);

      expect(fixture.store.goalWriteAttempts, 0);
      expect(fixture.goals.goals, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byKey(const ValueKey('recommended-goal-view')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Same-frame lock then unlock cycle while date sheet is open proactively dismisses date sheet and prevents writes',
    (tester) async {
      final fixture = await _mountPicker(tester);
      await _openPicker(tester);
      await _switchToHealth(tester);

      await _tapAnnualCheckup(tester);
      await _selectExplicitFutureDate(tester);

      final accessGeneration = fixture.lock.accessGeneration;
      fixture.lock.setLocked(true);
      fixture.lock.setLocked(false);
      expect(fixture.lock.isLocked, isFalse);
      expect(fixture.lock.accessGeneration, accessGeneration + 2);
      await _pumpFrames(tester, count: 5);

      final confirmFinder = find.widgetWithText(
        FilledButton,
        I18n.tr('action.confirm'),
      );
      if (confirmFinder.evaluate().isNotEmpty) {
        await tester.tap(confirmFinder);
        await _pumpFrames(tester, count: 15);
      } else {
        expect(
          find.byType(AppModalSheet),
          findsNothing,
          reason:
              'Owned date sheet was proactively removed by lock invalidation',
        );
      }
      await _drainWrites(tester);

      expect(fixture.store.goalWriteAttempts, 0);
      expect(fixture.goals.goals, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byKey(const ValueKey('recommended-goal-view')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Account and storage reset while date sheet is open proactively dismisses date sheet and prevents writes',
    (tester) async {
      final fixture = await _mountPicker(tester);
      await _openPicker(tester);
      await _switchToHealth(tester);

      await _tapAnnualCheckup(tester);
      await _selectExplicitFutureDate(tester);

      AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      fixture.goals.resetLocalState();
      await tester.pump();

      final confirmFinder = find.widgetWithText(
        FilledButton,
        I18n.tr('action.confirm'),
      );
      if (confirmFinder.evaluate().isNotEmpty) {
        await tester.tap(confirmFinder);
        await _pumpFrames(tester, count: 15);
      } else {
        expect(
          find.byType(AppModalSheet),
          findsNothing,
          reason:
              'Owned date sheet was proactively removed by storage reset invalidation',
        );
      }
      await _drainWrites(tester);

      expect(fixture.store.goalWriteAttempts, 0);
      expect(fixture.goals.goals, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byKey(const ValueKey('recommended-goal-view')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Auth token ABA transition while date sheet is open proactively dismisses date sheet and prevents writes',
    (tester) async {
      final fixture = await _mountPicker(tester);
      await _openPicker(tester);
      await _switchToHealth(tester);

      await _tapAnnualCheckup(tester);
      await _selectExplicitFutureDate(tester);

      fixture.auth.triggerTokenAba();
      await tester.pump();

      final confirmFinder = find.widgetWithText(
        FilledButton,
        I18n.tr('action.confirm'),
      );
      if (confirmFinder.evaluate().isNotEmpty) {
        await tester.tap(confirmFinder);
        await _pumpFrames(tester, count: 15);
      } else {
        expect(
          find.byType(AppModalSheet),
          findsNothing,
          reason:
              'Owned date sheet was proactively removed by auth session invalidation',
        );
      }
      await _drainWrites(tester);

      expect(fixture.store.goalWriteAttempts, 0);
      expect(fixture.goals.goals, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byKey(const ValueKey('recommended-goal-view')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Switching to lunar calendar in date sheet and confirming produces valid solar target date',
    (tester) async {
      final fixture = await _mountPicker(tester);
      await _openPicker(tester);
      await _switchToHealth(tester);

      await _tapAnnualCheckup(tester);

      final lunarSegment = find.text(I18n.tr('calendar.lunar'));
      expect(lunarSegment, findsOneWidget);
      await tester.tap(lunarSegment);
      await _pumpFrames(tester, count: 5);

      await _confirmDate(tester);
      await _drainWrites(tester);

      expect(fixture.store.goalWriteAttempts, 1);
      expect(fixture.goals.goals, hasLength(1));
      final savedGoal = fixture.goals.goals.first;
      expect(savedGoal.targetDate, isNotNull);
      expect(savedGoal.reminder.daysBefore, 3);
      expect(isGoalValid(savedGoal), isTrue);
      expect(
        find.byKey(const ValueKey('recommended-goal-view')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Mandatory app update activation while date sheet is open proactively dismisses date sheet and prevents writes',
    (tester) async {
      final fixture = await _mountPicker(tester);
      await _openPicker(tester);
      await _switchToHealth(tester);

      await _tapAnnualCheckup(tester);
      await _selectExplicitFutureDate(tester);

      fixture.update.setMustUpdate(true);
      await tester.pump();

      final confirmFinder = find.widgetWithText(
        FilledButton,
        I18n.tr('action.confirm'),
      );
      if (confirmFinder.evaluate().isNotEmpty) {
        await tester.tap(confirmFinder);
        await _pumpFrames(tester, count: 15);
      } else {
        expect(
          find.byType(AppModalSheet),
          findsNothing,
          reason:
              'Owned date sheet was proactively removed by update invalidation',
        );
      }
      await _drainWrites(tester);

      expect(fixture.store.goalWriteAttempts, 0);
      expect(fixture.goals.goals, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byKey(const ValueKey('recommended-goal-view')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

Finder _category(String category) =>
    find.byKey(ValueKey('recommended-category-$category'));

Finder _goalList(String category) =>
    find.byKey(PageStorageKey<String>('recommended-goal-list-$category'));

Finder _addButton(String id) => find.byKey(ValueKey('recommended-add-$id'));

DateTime _deriveFutureTargetDate([DateTime? base]) {
  final now = base ?? DateTime.now();
  final nextYear = now.month == 12 ? now.year + 1 : now.year;
  final nextMonth = now.month == 12 ? 1 : now.month + 1;
  return DateTime(nextYear, nextMonth, 15);
}

Future<void> _openPicker(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('open-recommended-goals')));
  await tester.pumpAndSettle();
  expect(find.byType(RecommendedGoalsPicker), findsOneWidget);
}

Future<void> _switchToHealth(WidgetTester tester) async {
  await tester.tap(_category('health'));
  await tester.pumpAndSettle();
}

Future<void> _waitForModalSheet(WidgetTester tester) async {
  final sheetFinder = find.byType(AppModalSheet);
  final confirmFinder = find.descendant(
    of: sheetFinder,
    matching: find.byType(FilledButton),
  );
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (sheetFinder.evaluate().isNotEmpty &&
        confirmFinder.evaluate().isNotEmpty) {
      for (var frame = 0; frame < 10; frame++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      return;
    }
  }
  expect(sheetFinder, findsOneWidget);
  expect(confirmFinder, findsOneWidget);
}

Future<void> _tapAnnualCheckup(WidgetTester tester) async {
  final addFinder = _addButton('rec.health.annual_checkup');
  await tester.scrollUntilVisible(
    addFinder,
    100,
    scrollable: find.descendant(
      of: _goalList('health'),
      matching: find.byType(Scrollable),
    ),
  );
  await tester.tap(addFinder);
  await _waitForModalSheet(tester);
}

DateTime _detectCurrentPickerMonth({DateTime? base}) {
  final center = base ?? DateTime.now();
  for (var delta = -24; delta <= 24; delta++) {
    final candidate = DateTime(center.year, center.month + delta);
    final text = I18nDateFormat.yearMonth(candidate);
    if (find
        .descendant(of: find.byType(AppModalSheet), matching: find.text(text))
        .evaluate()
        .isNotEmpty) {
      return candidate;
    }
  }
  return DateTime(center.year, center.month);
}

Future<DateTime> _selectExplicitFutureDate(
  WidgetTester tester, {
  DateTime? target,
}) async {
  final targetDate = target ?? _deriveFutureTargetDate();
  final dayKey = ValueKey(
    'solar-day-${targetDate.year}-${targetDate.month.toString().padLeft(2, '0')}-15',
  );

  if (find.byKey(dayKey).evaluate().isEmpty) {
    final currentMonth = _detectCurrentPickerMonth(base: targetDate);
    final diff =
        (targetDate.year - currentMonth.year) * 12 +
        (targetDate.month - currentMonth.month);

    if (diff > 0) {
      final nextMonthBtn = find.descendant(
        of: find.byType(AppModalSheet),
        matching: find.byTooltip(I18n.tr('picker.date.next_month')),
      );
      for (var i = 0; i < diff; i++) {
        expect(nextMonthBtn, findsOneWidget);
        await tester.tap(nextMonthBtn);
        await _pumpFrames(tester, count: 5);
      }
    } else if (diff < 0) {
      final prevMonthBtn = find.descendant(
        of: find.byType(AppModalSheet),
        matching: find.byTooltip(I18n.tr('picker.date.prev_month')),
      );
      for (var i = 0; i < -diff; i++) {
        expect(prevMonthBtn, findsOneWidget);
        await tester.tap(prevMonthBtn);
        await _pumpFrames(tester, count: 5);
      }
    }
  }

  final dayCell = find.byKey(dayKey);
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (dayCell.evaluate().isNotEmpty) break;
  }
  expect(dayCell, findsOneWidget);
  await tester.tap(dayCell);
  await _pumpFrames(tester, count: 5);

  return targetDate;
}

Future<void> _confirmDate(WidgetTester tester) async {
  final confirmBtn = find.descendant(
    of: find.byType(AppModalSheet),
    matching: find.byType(FilledButton),
  );
  expect(confirmBtn, findsOneWidget);
  await tester.tap(confirmBtn);
  await _pumpFrames(tester, count: 15);
}

Future<void> _cancelDate(WidgetTester tester) async {
  final cancelBtn = find.descendant(
    of: find.byType(AppModalSheet),
    matching: find.widgetWithText(TextButton, I18n.tr('action.cancel')),
  );
  expect(cancelBtn, findsOneWidget);
  await tester.tap(cancelBtn);
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (find.byType(AppModalSheet).evaluate().isEmpty &&
        find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      break;
    }
  }
  expect(find.byType(AppModalSheet), findsNothing);
}

Future<void> _drainWrites(WidgetTester tester) async {
  for (var frame = 0; frame < 5; frame++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  for (var i = 0; i < 35; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (find.byType(AppModalSheet).evaluate().isEmpty &&
        find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      break;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  await tester.runAsync(() async {
    await AccountPreferenceWrites.drain().timeout(const Duration(seconds: 5));
  });
  for (var frame = 0; frame < 10; frame++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> _pumpFrames(WidgetTester tester, {required int count}) async {
  for (var frame = 0; frame < count; frame++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> _waitForHeldWrite(WidgetTester tester, _GoalStore store) async {
  for (var attempt = 0; attempt < 10; attempt++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (store.started.isCompleted) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    if (store.started.isCompleted) return;
  }
  expect(store.started.isCompleted, isTrue, reason: 'held goal write started');
}

Future<void> _releaseHeldWrite(WidgetTester tester, _Fixture fixture) async {
  if (!fixture.store.release.isCompleted) fixture.store.release.complete();
  await _pumpFrames(tester, count: 5);
  await tester.runAsync(
    () => AccountPreferenceWrites.drain().timeout(const Duration(seconds: 5)),
  );
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      break;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  for (var frame = 0; frame < 10; frame++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<_Fixture> _mountPicker(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  AppLocale initialLocale = AppLocale.zh,
}) async {
  final fixture = _Fixture();
  SharedPreferencesStorePlatform.instance = fixture.store;
  await tester.runAsync(fixture.goals.loadFromStorage);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  I18n.setLocale(initialLocale);

  addTearDown(() async {
    if (!fixture.store.release.isCompleted) fixture.store.release.complete();
    await _pumpFrames(tester, count: 5);
    await tester.runAsync(() async {
      await AccountPreferenceWrites.drain().timeout(const Duration(seconds: 5));
    });
    await tester.pumpWidget(const SizedBox.shrink());
    fixture.routeGate.dispose();
    fixture.goals.dispose();
    fixture.lock.dispose();
    fixture.lockSource.dispose();
    fixture.auth.dispose();
    fixture.update.dispose();
    tester.view.reset();
  });

  final theme = AppBrands.defaultBrand.theme.copyWith(
    platform: TargetPlatform.iOS,
  );

  await tester.pumpWidget(
    ValueListenableBuilder<AppLockProvider>(
      valueListenable: fixture.lockSource,
      builder: (context, lock, _) => MultiProvider(
        providers: [
          ChangeNotifierProvider<GoalProvider>.value(value: fixture.goals),
          ChangeNotifierProvider<AppLockProvider>.value(value: lock),
          ChangeNotifierProvider<AuthProvider>.value(value: fixture.auth),
          ChangeNotifierProvider<AppUpdateService>.value(value: fixture.update),
        ],
        child: MaterialApp(
          navigatorKey: fixture.navigator,
          navigatorObservers: [fixture.routeGate],
          theme: theme,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  key: const ValueKey('open-recommended-goals'),
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => const RecommendedGoalsPicker(),
                    ),
                  ),
                  child: const Text('Open recommended goals'),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fixture;
}

class _Fixture {
  final goals = GoalProvider();
  final lock = _PickerLock();
  late final lockSource = ValueNotifier<AppLockProvider>(lock);
  final auth = _TestAuthProvider();
  final update = _TestUpdateService();
  final store = _GoalStore();
  final navigator = GlobalKey<NavigatorState>();
  final routeGate = AppAccessRouteGate();
}

class _GoalStore extends InMemorySharedPreferencesStore {
  _GoalStore() : super.withData(<String, Object>{});

  int goalWriteAttempts = 0;
  bool holdNextGoalWrite = false;
  bool failNextGoalWrite = false;
  Completer<void> started = Completer<void>();
  Completer<void> release = Completer<void>();

  void armHold() {
    holdNextGoalWrite = true;
    started = Completer<void>();
    release = Completer<void>();
  }

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key == 'flutter.duoyi_goals') {
      goalWriteAttempts++;
      if (holdNextGoalWrite) {
        holdNextGoalWrite = false;
        started.complete();
        await release.future;
      }
      if (failNextGoalWrite) {
        failNextGoalWrite = false;
        return false;
      }
    }
    return super.setValue(type, key, value);
  }
}

class _PickerLock extends AppLockProvider {
  bool _locked = false;
  int _accessGeneration = 0;

  @override
  bool get isLocked => _locked;

  @override
  int get accessGeneration => _accessGeneration;

  void setLocked(bool value) {
    if (_locked == value) return;
    _locked = value;
    _accessGeneration++;
    notifyListeners();
  }
}

class _TestAuthProvider extends AuthProvider {
  _TestAuthProvider({
    super.initialState = const AuthState(userId: 'test_user', token: 'token_a'),
  }) : _stateOverride = initialState,
       super(
         client: ApiClient(
           baseUrl: 'http://127.0.0.1:9',
           token: initialState.token,
           httpClient: MockClient((_) async => http.Response('{}', 200)),
         ),
       );

  AuthState _stateOverride;
  int _sessionGenerationOverride = 1;
  bool _leaseInvalidated = false;

  @override
  AuthState get state => _stateOverride;

  @override
  int get sessionGeneration => _sessionGenerationOverride;

  @override
  bool isSessionLeaseCurrent(AuthSessionLease lease) {
    if (_leaseInvalidated) return false;
    return super.isSessionLeaseCurrent(lease);
  }

  void triggerTokenAba() {
    _sessionGenerationOverride++;
    _leaseInvalidated = true;
    _stateOverride = const AuthState(userId: 'test_user_2', token: 'token_b');
    notifyListeners();
    _sessionGenerationOverride++;
    _stateOverride = const AuthState(userId: 'test_user', token: 'token_a');
    notifyListeners();
  }
}

class _TestUpdateService extends AppUpdateService {
  _TestUpdateService()
    : super(
        repo: 'test/repo',
        currentVersion: '1.0.0',
        httpClient: MockClient((_) async => http.Response('{}', 200)),
      );

  bool _forced = false;

  @override
  bool get mustUpdate => _forced;

  void setMustUpdate(bool value) {
    if (_forced == value) return;
    _forced = value;
    notifyListeners();
  }
}
