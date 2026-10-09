import 'package:duoyi/core/heatmap_calendar.dart';
import 'package:duoyi/models/habit.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _key(DateTime day) => HeatmapCalendarWindow.dateKey(day);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HeatmapCalendarWindow', () {
    test('starts on Monday and includes only elapsed dates through Sunday', () {
      final monday = HeatmapCalendarWindow(
        weeks: 1,
        today: DateTime(2024, 1, 1, 23, 45),
      );

      expect(monday.start, DateTime(2024, 1, 1));
      expect(monday.today, DateTime(2024, 1, 1));
      expect(monday.elapsedDays, 1);
      expect(monday.visibleDays.map(_key), ['2024-01-01']);

      final sunday = HeatmapCalendarWindow(
        weeks: 1,
        today: DateTime(2023, 12, 31),
      );
      expect(sunday.start, DateTime(2023, 12, 25));
      expect(sunday.elapsedDays, 7);
      expect(sunday.dayAt(6), DateTime(2023, 12, 31));
      expect(sunday.visibleDays.map(_key).last, '2023-12-31');
    });

    test('traverses New Year and leap day by consecutive civil dates', () {
      final newYear = HeatmapCalendarWindow(
        weeks: 2,
        today: DateTime(2024, 1, 1),
      );
      expect(newYear.start, DateTime(2023, 12, 25));
      expect(newYear.dayAt(6), DateTime(2023, 12, 31));
      expect(newYear.dayAt(7), DateTime(2024, 1, 1));

      final leapWindow = HeatmapCalendarWindow(
        weeks: 1,
        today: DateTime(2024, 3, 1),
      );
      expect(leapWindow.start, DateTime(2024, 2, 26));
      expect(leapWindow.visibleDays.map(_key), [
        '2024-02-26',
        '2024-02-27',
        '2024-02-28',
        '2024-02-29',
        '2024-03-01',
      ]);
      expect(leapWindow.dayAt(3), DateTime(2024, 2, 29));
    });

    test(
      'day shifts and distances ignore clock time and preserve civil days',
      () {
        final lateDay = DateTime(2024, 3, 10, 23, 59);
        final nextDay = HeatmapCalendarWindow.shiftDay(lateDay, 1);

        expect(nextDay, DateTime(2024, 3, 11));
        expect(
          HeatmapCalendarWindow.dayDistance(
            DateTime(2024, 3, 10, 23),
            DateTime(2024, 3, 11, 1),
          ),
          1,
        );
        expect(
          HeatmapCalendarWindow.dateKey(DateTime(2024, 3, 10, 23, 59)),
          '2024-03-10',
        );
      },
    );

    test(
      'contains the whole current date but excludes dates outside the window',
      () {
        final window = HeatmapCalendarWindow(
          weeks: 2,
          today: DateTime(2024, 1, 10),
        );

        expect(window.start, DateTime(2024, 1, 1));
        expect(window.contains(DateTime(2024, 1, 1, 23, 59)), isTrue);
        expect(window.contains(DateTime(2024, 1, 10, 23, 59)), isTrue);
        expect(window.contains(DateTime(2023, 12, 31)), isFalse);
        expect(window.contains(DateTime(2024, 1, 11)), isFalse);
        expect(window.visibleDays.last, DateTime(2024, 1, 10));
      },
    );

    test(
      'clamps levels and summarizes only visible dates, excluding future data',
      () {
        final window = HeatmapCalendarWindow(
          weeks: 1,
          today: DateTime(2024, 2, 29),
        );
        final summary = window.summarize({
          '2024-02-25': 5,
          '2024-02-26': 0,
          '2024-02-27': 1,
          '2024-02-28': 1,
          '2024-02-29': 9,
          '2024-03-01': 5,
        });

        expect(HeatmapCalendarWindow.level(null), 0);
        expect(HeatmapCalendarWindow.level(-3), 0);
        expect(HeatmapCalendarWindow.level(6), 5);
        expect(summary.activeDays, 3);
        expect(summary.maximumLevel, 5);

        final emptySummary = window.summarize({
          '2024-02-25': 5,
          '2024-03-01': 5,
        });
        expect(emptySummary.activeDays, 0);
        expect(emptySummary.maximumLevel, 0);
      },
    );

    test('maps progress ratio thresholds to the five visible levels', () {
      expect(HeatmapCalendarWindow.progressLevel(-0.2), 0);
      expect(HeatmapCalendarWindow.progressLevel(0), 0);
      expect(HeatmapCalendarWindow.progressLevel(0.01), 1);
      expect(HeatmapCalendarWindow.progressLevel(0.2), 1);
      expect(HeatmapCalendarWindow.progressLevel(0.21), 2);
      expect(HeatmapCalendarWindow.progressLevel(0.4), 2);
      expect(HeatmapCalendarWindow.progressLevel(0.41), 3);
      expect(HeatmapCalendarWindow.progressLevel(0.61), 4);
      expect(HeatmapCalendarWindow.progressLevel(0.81), 5);
      expect(HeatmapCalendarWindow.progressLevel(2), 5);
    });

    test('parses only real, fixed-width civil date keys', () {
      expect(HeatmapCalendarWindow.dateKey(DateTime(1, 1, 1)), '0001-01-01');
      expect(
        HeatmapCalendarWindow.tryParseDateKey('2024-02-29'),
        DateTime(2024, 2, 29),
      );
      expect(
        HeatmapCalendarWindow.tryParseDateKey('0001-01-01'),
        DateTime(1, 1, 1),
      );
      expect(HeatmapCalendarWindow.tryParseDateKey('2023-02-29'), isNull);
      expect(HeatmapCalendarWindow.tryParseDateKey('2024-2-09'), isNull);
      expect(HeatmapCalendarWindow.tryParseDateKey('2024-02-30'), isNull);
      expect(HeatmapCalendarWindow.tryParseDateKey('0000-01-01'), isNull);
    });

    test(
      'low-year habit output is padded while legacy completion keys still read',
      () {
        final habit = Habit(
          id: 'heatmap-low-year-fixture',
          name: 'Old completion',
          targetCount: 1,
          completions: const {'1-01-01': 1},
        );

        expect(habit.heatmapData(1, today: DateTime(1, 1, 1)), {
          '0001-01-01': 5,
        });
      },
    );

    test(
      'habit heatmap respects partial and over-target progress, weekdays and today',
      () {
        final habit = Habit(
          id: 'heatmap-progress-fixture',
          name: 'Read',
          targetCount: 4,
          activeWeekdays: const [
            3,
          ], // Thursday, using DateTime weekday minus one.
          completions: const {
            '2024-02-22': 5,
            '2024-02-29': 1,
            '2024-03-01': 4, // Inactive Friday must remain zero.
          },
        );

        final data = habit.heatmapData(2, today: DateTime(2024, 3, 1));

        expect(data['2024-02-22'], 5);
        expect(data['2024-02-28'], 0);
        expect(data['2024-02-29'], 2);
        expect(data['2024-03-01'], 0);
      },
    );

    test(
      'negative habit heatmap maps no setback to success and a setback to zero',
      () {
        final habit = Habit(
          id: 'heatmap-negative-fixture',
          name: 'No late night snacks',
          kind: HabitKind.negative,
          completions: const {'2024-02-28': 1},
        );

        final data = habit.heatmapData(1, today: DateTime(2024, 2, 29));

        expect(data['2024-02-26'], 5);
        expect(data['2024-02-27'], 5);
        expect(data['2024-02-28'], 0);
        expect(data['2024-02-29'], 5);
      },
    );

    test(
      'flex heatmap uses its weekly completion ratio for every visible day',
      () {
        final habit = Habit(
          id: 'heatmap-flex-fixture',
          name: 'Exercise',
          flexTarget: 4,
          flexPeriod: HabitFlexPeriod.week,
          completions: const {'2024-02-26': 1, '2024-02-27': 1},
        );

        final data = habit.heatmapData(1, today: DateTime(2024, 2, 29));

        expect(data.values, [3, 3, 3, 3]);
      },
    );

    test('combined heatmap averages only habits active on each date', () async {
      SharedPreferences.setMockInitialValues({});
      final provider = HabitProvider();
      await provider.importHabits([
        Habit(
          id: 'heatmap-active-monday',
          name: 'Monday habit',
          activeWeekdays: const [0],
          targetCount: 2,
          completions: const {'2026-05-04': 1},
        ),
        Habit(
          id: 'heatmap-inactive-monday',
          name: 'Tuesday habit',
          activeWeekdays: const [1],
          targetCount: 1,
        ),
      ]);

      final combined = provider.combinedHeatmap(1, today: DateTime(2026, 5, 4));

      expect(combined, {'2026-05-04': 3});
      provider.dispose();
    });

    test('rejects a zero-week window', () {
      expect(
        () => HeatmapCalendarWindow(weeks: 0, today: DateTime(2024, 1, 1)),
        throwsRangeError,
      );
    });
  });
}
