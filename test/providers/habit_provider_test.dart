import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:duoyi/models/habit.dart';
import 'package:duoyi/models/time_entry.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';

import '../test_support/recording_reminder_scheduler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
    'incrementHabitForDate backfills the selected day and can undo it',
    () async {
      final audit = TimeAuditProvider();
      await audit.loadFromStorage();

      final provider = HabitProvider()..timeAudit = audit;
      final habit = Habit(
        id: 'habit-1',
        name: '阅读',
        targetCount: 30,
        unit: '分钟',
        createdAt: DateTime(2026, 5, 1),
      );
      await provider.addHabit(habit);

      final backfillDate = DateTime(2026, 5, 12);
      await provider.incrementHabitForDate(habit.id, backfillDate);

      expect(provider.habits.single.countForDate(backfillDate), 30);
      final incrementStamp =
          provider.habits.single.completionUpdatedAt['2026-05-12'];
      expect(incrementStamp, isNotNull);
      expect(provider.habits.single.updatedAt, incrementStamp);
      expect(provider.habits.single.todayCount(), 0);
      expect(audit.entries.single.source, TimeEntrySource.habit);
      expect(audit.entries.single.sourceId, habit.id);
      expect(audit.entries.single.dayKey, '2026-05-12');
      expect(audit.entries.single.durationSeconds, 30 * 60);

      await Future<void>.delayed(const Duration(milliseconds: 1));
      await provider.decrementHabitForDate(habit.id, backfillDate);

      expect(provider.habits.single.countForDate(backfillDate), 0);
      expect(
        provider.habits.single.completions.containsKey('2026-05-12'),
        isFalse,
      );
      final tombstoneStamp =
          provider.habits.single.completionUpdatedAt['2026-05-12'];
      expect(tombstoneStamp, isNotNull);
      expect(tombstoneStamp!.isAfter(incrementStamp!), isTrue);
      expect(provider.habits.single.updatedAt, tombstoneStamp);
      expect(audit.entries, isEmpty);
    },
  );

  test('incrementHabitForDate ignores dates outside the habit range', () async {
    final audit = TimeAuditProvider();
    await audit.loadFromStorage();

    final provider = HabitProvider()..timeAudit = audit;
    final habit = Habit(
      id: 'range-habit',
      name: '阶段阅读',
      targetCount: 1,
      unit: '分钟',
      startDate: DateTime(2026, 5, 10),
      endDate: DateTime(2026, 5, 12),
    );
    await provider.addHabit(habit);

    await provider.incrementHabitForDate(habit.id, DateTime(2026, 5, 9));
    await provider.incrementHabitForDate(habit.id, DateTime(2026, 5, 13));

    expect(provider.habits.single.completions, isEmpty);
    expect(audit.entries, isEmpty);

    await provider.incrementHabitForDate(habit.id, DateTime(2026, 5, 10));

    expect(provider.habits.single.countForDate(DateTime(2026, 5, 10)), 1);
    expect(audit.entries, hasLength(1));
  });

  test('habit check-in still notifies when time audit write fails', () async {
    final provider = HabitProvider()..timeAudit = _FailingTimeAuditProvider();
    final habit = Habit(
      id: 'audit-fails',
      name: '阅读',
      targetCount: 30,
      unit: '分钟',
    );
    await provider.addHabit(habit);

    var notifications = 0;
    provider.addListener(() => notifications++);

    await provider.incrementHabit(habit.id);

    expect(provider.habits.single.todayCount(), 30);
    expect(notifications, greaterThanOrEqualTo(1));

    await provider.decrementHabit(habit.id);

    expect(provider.habits.single.todayCount(), 0);
    expect(notifications, greaterThanOrEqualTo(2));
  });

  test(
    'current week progress refreshes immediately after today check-in',
    () async {
      final provider = HabitProvider();
      final todayIndex = DateTime.now().weekday - 1;
      await provider.addHabit(
        Habit(id: 'weekly-progress', name: '阅读', targetCount: 1),
      );

      expect(provider.currentWeekProgress()[todayIndex], 0);

      await provider.incrementHabit('weekly-progress');

      expect(provider.currentWeekProgress()[todayIndex], 1);
    },
  );

  test(
    'combined heatmap and weekly completion skip inactive date ranges',
    () async {
      final provider = HabitProvider();
      final today = DateTime.now();
      final todayKey =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      await provider.addHabit(
        Habit(
          id: 'ended',
          name: '已结束',
          targetCount: 1,
          endDate: today.subtract(const Duration(days: 1)),
          completions: {todayKey: 1},
        ),
      );

      final heatmap = provider.combinedHeatmap(1);
      final weekly = provider.last7DaysCompletion();

      expect(heatmap[todayKey], 0);
      expect(weekly.last, 0);
    },
  );

  test('endHabit keeps today visible when today has a record', () async {
    final provider = HabitProvider();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todayKey = Habit(id: 'key-helper', name: 'helper').todayKey();
    await provider.addHabit(
      Habit(
        id: 'completed-today',
        name: '阅读',
        targetCount: 1,
        completions: {todayKey: 1},
      ),
    );

    expect(provider.habits.single.isCompletedToday(), isTrue);
    expect(provider.todayCompletionRate, 1);

    await provider.endHabit('completed-today', at: today);

    final ended = provider.habits.single;
    expect(ended.endDate, today);
    expect(ended.isActiveToday(), isTrue);
    expect(ended.isCompletedToday(), isTrue);
    expect(provider.todayCompletionRate, 1);
    expect(provider.todayOverallProgress, 1);
  });

  test(
    'habit saves sync reminders immediately when scheduler is injected',
    () async {
      final scheduler = RecordingReminderScheduler();
      final provider = HabitProvider()..scheduler = scheduler;
      final habit = Habit(
        id: 'habit-sync',
        name: '阅读',
        remind: true,
        remindHour: 9,
        remindMinute: 0,
      );

      await provider.addHabit(habit);
      expect(scheduler.habitSyncs, [
        ['habit-sync'],
      ]);

      await provider.updateHabit(
        habit.id,
        habit.copyWith(remindHour: 10, remindMinute: 30),
      );
      expect(scheduler.habitSyncs, [
        ['habit-sync'],
        ['habit-sync'],
      ]);

      await provider.deleteHabit(habit.id);
      expect(scheduler.habitSyncs.last, isEmpty);
    },
  );
}

class _FailingTimeAuditProvider extends TimeAuditProvider {
  @override
  Future<void> recordHabitCheckIn(
    Habit habit, {
    required int cumulativeCount,
    int amount = 1,
    DateTime? at,
  }) async {
    throw StateError('time audit unavailable');
  }

  @override
  Future<void> removeHabitCheckIn(
    Habit habit, {
    required int count,
    DateTime? at,
  }) async {
    throw StateError('time audit unavailable');
  }
}
