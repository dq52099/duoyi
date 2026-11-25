import 'package:duoyi/services/widget_habit_progress.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('widget habit incomplete sets cannot round to full completion', () {
    for (final counts in [(200, 201), (999, 1000), (4999, 5000)]) {
      expect(
        widgetHabitCompletionPercent(
          completedCount: counts.$1,
          activeCount: counts.$2,
        ),
        99,
        reason: '${counts.$1} of ${counts.$2} completed',
      );
    }
  });

  test('widget habit empty and not started sets retain zero progress', () {
    for (final count in [0, 1, 201, 5000]) {
      expect(
        widgetHabitCompletionPercent(activeCount: count, completedCount: 0),
        0,
      );
    }
  });

  test('widget habit fully completed sets retain full completion', () {
    for (final count in [1, 3, 201, 5000]) {
      expect(
        widgetHabitCompletionPercent(activeCount: count, completedCount: count),
        100,
      );
    }
  });

  test('widget habit ordinary progress retains existing rounded values', () {
    for (final counts in [(1, 3, 33), (2, 3, 67), (1, 8, 13), (3, 4, 75)]) {
      expect(
        widgetHabitCompletionPercent(
          completedCount: counts.$1,
          activeCount: counts.$2,
        ),
        counts.$3,
      );
    }
  });
}
