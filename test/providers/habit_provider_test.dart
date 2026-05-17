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
        targetCount: 2,
        unit: '分钟',
        createdAt: DateTime(2026, 5, 1),
      );
      await provider.addHabit(habit);

      final backfillDate = DateTime(2026, 5, 12);
      await provider.incrementHabitForDate(habit.id, backfillDate);

      expect(provider.habits.single.countForDate(backfillDate), 1);
      expect(provider.habits.single.todayCount(), 0);
      expect(audit.entries.single.source, TimeEntrySource.habit);
      expect(audit.entries.single.sourceId, habit.id);
      expect(audit.entries.single.dayKey, '2026-05-12');

      await provider.decrementHabitForDate(habit.id, backfillDate);

      expect(provider.habits.single.countForDate(backfillDate), 0);
      expect(
        provider.habits.single.completions.containsKey('2026-05-12'),
        isFalse,
      );
      expect(audit.entries, isEmpty);
    },
  );
}
