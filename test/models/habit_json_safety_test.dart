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
}
