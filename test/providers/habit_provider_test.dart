import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:duoyi/models/habit.dart';
import 'package:duoyi/models/time_entry.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';

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
      expect(provider.habits.single.todayCount(), 0);
      expect(audit.entries.single.source, TimeEntrySource.habit);
      expect(audit.entries.single.sourceId, habit.id);
      expect(audit.entries.single.dayKey, '2026-05-12');
      expect(audit.entries.single.durationSeconds, 30 * 60);

      await provider.decrementHabitForDate(habit.id, backfillDate);

      expect(provider.habits.single.countForDate(backfillDate), 0);
      expect(
        provider.habits.single.completions.containsKey('2026-05-12'),
        isFalse,
      );
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
}
