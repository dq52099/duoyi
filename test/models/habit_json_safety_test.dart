import 'package:flutter_test/flutter_test.dart';
import 'package:duoyi/models/habit.dart';

void main() {
  test(
    'Habit.fromJson tolerates legacy sparse data and safe heatmap target',
    () {
      final habit = Habit.fromJson(<String, dynamic>{
        'id': 'legacy-habit',
        'name': 'Legacy',
        'kind': 99,
        'targetCount': 0,
        'completions': {'2026-05-12': 2.0},
      });

      expect(habit.id, 'legacy-habit');
      expect(habit.kind, HabitKind.negative);
      expect(habit.targetCount, 1);
      expect(habit.createdAt, isA<DateTime>());
      expect(() => habit.heatmapData(1), returnsNormally);
    },
  );

  test('negative habit treats zero occurrences as complete progress', () {
    final habit = Habit(
      id: 'negative-habit',
      name: '少刷短视频',
      kind: HabitKind.negative,
      targetCount: 1,
    );

    expect(habit.todayCount(), 0);
    expect(habit.todayProgress(), 1.0);
    expect(habit.isCompletedToday(), isTrue);

    habit.completions[habit.todayKey()] = 1;

    expect(habit.todayProgress(), 0.0);
    expect(habit.isCompletedToday(), isFalse);
  });
}
