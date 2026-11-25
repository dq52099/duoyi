import 'dart:convert';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/goal_validation.dart';
import 'package:duoyi/core/recommended_goals.dart';
import 'package:duoyi/models/goal.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'advance reminder recommendation requires a date before any write',
    () async {
      final store = _RecordingStore();
      SharedPreferencesStorePlatform.instance = store;
      final provider = GoalProvider();
      addTearDown(provider.dispose);
      final annual = RecommendedGoalsLibrary.all().singleWhere(
        (goal) => goal.id == 'rec.health.annual_checkup',
      );
      Object? failure;
      try {
        await provider.applyRecommended(annual);
      } catch (error) {
        failure = error;
      }
      expect(
        store.goalWrites,
        0,
        reason: 'No unanchored reminder may be persisted.',
      );
      expect(provider.goals, isEmpty);
      expect(failure, isA<ArgumentError>());
      expect((failure as ArgumentError).name, 'targetDate');
    },
  );

  test(
    'explicit annual date persists the unchanged advance reminder',
    () async {
      final provider = GoalProvider();
      addTearDown(provider.dispose);
      final annual = RecommendedGoalsLibrary.all().singleWhere(
        (goal) => goal.id == 'rec.health.annual_checkup',
      );
      final chosen = DateTime(2035, 3, 17);
      final saved = await provider.applyRecommended(annual, targetDate: chosen);
      expect(saved.targetDate, chosen);
      expect(saved.reminder.toJson(), annual.reminder.toJson());
      expect(
        saved.reminderPlan.rules.single.type,
        ReminderRuleType.relativeToDue,
      );
      expect(saved.reminderPlan.rules.single.offsetMinutes, -3 * 24 * 60);
      expect(validateGoal(saved), isEmpty);
      final prefs = await SharedPreferences.getInstance();
      final restored = GoalItem.fromJson(
        jsonDecode(prefs.getStringList('duoyi_goals')!.single),
      );
      expect(restored.targetDate, chosen);
      expect(restored.reminder.toJson(), annual.reminder.toJson());
    },
  );

  test(
    'all recommendations are valid after their required explicit input',
    () async {
      final provider = GoalProvider();
      addTearDown(provider.dispose);
      final chosen = DateTime(2035, 3, 17);
      for (final template in RecommendedGoalsLibrary.all()) {
        final saved = await provider.applyRecommended(
          template,
          targetDate: template.requiresTargetDate ? chosen : null,
        );
        expect(validateGoal(saved), isEmpty, reason: template.id);
        expect(saved.targetDate, template.requiresTargetDate ? chosen : null);
        expect(saved.reminder.toJson(), template.reminder.toJson());
      }
      expect(provider.goals, hasLength(RecommendedGoalsLibrary.all().length));
    },
  );

  for (final reminder in [
    const ReminderConfig(enabled: false, daysBefore: 3),
    const ReminderConfig(enabled: true, kind: ReminderKind.off, daysBefore: 3),
  ]) {
    test(
      'inactive advance reminder ${reminder.enabled}/${reminder.kind} needs no date',
      () async {
        final base = RecommendedGoalsLibrary.all().first;
        final template = RecommendedGoal(
          id: 'fixture.inactive',
          category: base.category,
          title: base.title,
          description: base.description,
          icon: base.icon,
          colorValue: base.colorValue,
          recurrence: base.recurrence,
          scheduling: base.scheduling,
          reminder: reminder,
        );
        expect(template.requiresTargetDate, isFalse);
        final provider = GoalProvider();
        addTearDown(provider.dispose);
        final saved = await provider.applyRecommended(template);
        expect(saved.targetDate, isNull);
        expect(validateGoal(saved), isEmpty);
      },
    );
  }

  test('supplying a date cannot bypass the original write authority', () async {
    final store = _RecordingStore();
    SharedPreferencesStorePlatform.instance = store;
    final provider = GoalProvider();
    addTearDown(provider.dispose);
    final annual = RecommendedGoalsLibrary.all().singleWhere(
      (goal) => goal.id == 'rec.health.annual_checkup',
    );
    await expectLater(
      provider.applyRecommended(
        annual,
        targetDate: DateTime(2035, 3, 17),
        canWrite: () => false,
      ),
      throwsA(isA<AccountPreferenceWriteCanceled>()),
    );
    expect(store.goalWrites, 0);
    expect(provider.goals, isEmpty);
  });

  test('pure template drafts never invent an advance-reminder anchor', () {
    final annual = RecommendedGoalsLibrary.all().singleWhere(
      (goal) => goal.id == 'rec.health.annual_checkup',
    );
    final draft = RecommendedGoalsLibrary.instantiate(annual);
    expect(annual.requiresTargetDate, isTrue);
    expect(draft.targetDate, isNull);
    expect(draft.reminder.toJson(), annual.reminder.toJson());
  });
}

class _RecordingStore extends InMemorySharedPreferencesStore {
  _RecordingStore() : super.withData({});
  int goalWrites = 0;

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key == 'flutter.duoyi_goals') goalWrites++;
    return super.setValue(type, key, value);
  }
}
