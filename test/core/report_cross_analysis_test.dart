import 'package:duoyi/core/report_cross_analysis.dart';
import 'package:test/test.dart';

void main() {
  group('ReportCrossAnalysis focus completion correlation', () {
    test('builds daily scatter points and strong positive correlation', () {
      final result = ReportCrossAnalysis.buildFocusCompletionCorrelation(
        start: DateTime(2026, 5, 1),
        end: DateTime(2026, 5, 3),
        bucket: ReportCrossAnalysisBucket.day,
        completions: [
          ReportCompletionRecord(completedAt: DateTime(2026, 5, 1, 18)),
          ReportCompletionRecord(completedAt: DateTime(2026, 5, 2, 18)),
          ReportCompletionRecord(completedAt: DateTime(2026, 5, 2, 19)),
          ReportCompletionRecord(completedAt: DateTime(2026, 5, 3, 18)),
          ReportCompletionRecord(completedAt: DateTime(2026, 5, 3, 19)),
          ReportCompletionRecord(completedAt: DateTime(2026, 5, 3, 20)),
        ],
        focusRecords: [
          ReportFocusRecord(
            endedAt: DateTime(2026, 5, 1, 10),
            durationSeconds: 30 * 60,
          ),
          ReportFocusRecord(
            endedAt: DateTime(2026, 5, 2, 10),
            durationSeconds: 60 * 60,
          ),
          ReportFocusRecord(
            endedAt: DateTime(2026, 5, 3, 10),
            durationSeconds: 90 * 60,
          ),
        ],
      );

      expect(result.points.map((point) => point.label), ['5/1', '5/2', '5/3']);
      expect(result.points.map((point) => point.focusMinutes), [30, 60, 90]);
      expect(result.points.map((point) => point.completedTodos), [1, 2, 3]);
      expect(result.coefficient, closeTo(1, 0.001));
      expect(result.strengthLabel, '强正相关');
    });

    test('returns null coefficient when one dimension is constant', () {
      final result = ReportCrossAnalysis.buildFocusCompletionCorrelation(
        start: DateTime(2026, 5, 1),
        end: DateTime(2026, 5, 2),
        bucket: ReportCrossAnalysisBucket.day,
        completions: [
          ReportCompletionRecord(completedAt: DateTime(2026, 5, 1, 18)),
          ReportCompletionRecord(completedAt: DateTime(2026, 5, 2, 18)),
        ],
        focusRecords: const [],
      );

      expect(result.coefficient, isNull);
      expect(result.hasData, isTrue);
      expect(result.strengthLabel, '样本不足');
    });
  });

  group('ReportCrossAnalysis habit todo correlation', () {
    test('builds daily habit and todo points with positive correlation', () {
      final result = ReportCrossAnalysis.buildHabitTodoCorrelation(
        start: DateTime(2026, 5, 1),
        end: DateTime(2026, 5, 3),
        bucket: ReportCrossAnalysisBucket.day,
        completions: [
          ReportCompletionRecord(completedAt: DateTime(2026, 5, 1, 18)),
          ReportCompletionRecord(completedAt: DateTime(2026, 5, 2, 18)),
          ReportCompletionRecord(completedAt: DateTime(2026, 5, 2, 19)),
          ReportCompletionRecord(completedAt: DateTime(2026, 5, 3, 18)),
          ReportCompletionRecord(completedAt: DateTime(2026, 5, 3, 19)),
          ReportCompletionRecord(completedAt: DateTime(2026, 5, 3, 20)),
        ],
        habitCompletions: [
          ReportHabitCompletionRecord(completedAt: DateTime(2026, 5, 1, 12)),
          ReportHabitCompletionRecord(completedAt: DateTime(2026, 5, 2, 12)),
          ReportHabitCompletionRecord(completedAt: DateTime(2026, 5, 2, 13)),
          ReportHabitCompletionRecord(completedAt: DateTime(2026, 5, 3, 12)),
          ReportHabitCompletionRecord(completedAt: DateTime(2026, 5, 3, 13)),
          ReportHabitCompletionRecord(completedAt: DateTime(2026, 5, 3, 14)),
        ],
      );

      expect(result.points.map((point) => point.label), ['5/1', '5/2', '5/3']);
      expect(result.points.map((point) => point.habitCheckIns), [1, 2, 3]);
      expect(result.points.map((point) => point.completedTodos), [1, 2, 3]);
      expect(result.pearson, closeTo(1, 0.001));
      expect(result.maxHabitCheckIns, 3);
      expect(result.maxCompletedTodos, 3);
    });

    test('top-level build includes habit todo correlation', () {
      final result = ReportCrossAnalysis.build(
        start: DateTime(2026, 5, 1),
        end: DateTime(2026, 5, 2),
        bucket: ReportCrossBucket.day,
        todoCompletions: [
          ReportCrossTodoCompletion(DateTime(2026, 5, 1, 18)),
          ReportCrossTodoCompletion(DateTime(2026, 5, 2, 18)),
          ReportCrossTodoCompletion(DateTime(2026, 5, 2, 19)),
        ],
        focusSessions: const [],
        habitCompletions: [
          ReportCrossHabitCompletion(DateTime(2026, 5, 1, 12)),
          ReportCrossHabitCompletion(DateTime(2026, 5, 2, 12)),
          ReportCrossHabitCompletion(DateTime(2026, 5, 2, 13)),
        ],
        timeEntries: const [],
      );

      expect(result.habitTodo.points.map((point) => point.habitCheckIns), [
        1,
        2,
      ]);
      expect(result.habitTodo.points.map((point) => point.completedTodos), [
        1,
        2,
      ]);
      expect(result.habitTodo.pearson, closeTo(1, 0.001));
    });
  });

  group('ReportCrossAnalysis diary focus correlation', () {
    test('builds daily diary and focus points with positive correlation', () {
      final result = ReportCrossAnalysis.buildDiaryFocusCorrelation(
        start: DateTime(2026, 5, 1),
        end: DateTime(2026, 5, 3),
        bucket: ReportCrossAnalysisBucket.day,
        diaryEntries: [
          ReportDiaryEntryRecord(writtenAt: DateTime(2026, 5, 1, 21)),
          ReportDiaryEntryRecord(writtenAt: DateTime(2026, 5, 2, 21)),
          ReportDiaryEntryRecord(writtenAt: DateTime(2026, 5, 2, 22)),
          ReportDiaryEntryRecord(writtenAt: DateTime(2026, 5, 3, 21)),
          ReportDiaryEntryRecord(writtenAt: DateTime(2026, 5, 3, 22)),
          ReportDiaryEntryRecord(writtenAt: DateTime(2026, 5, 3, 23)),
        ],
        focusRecords: [
          ReportFocusRecord(
            endedAt: DateTime(2026, 5, 1, 10),
            durationSeconds: 20 * 60,
          ),
          ReportFocusRecord(
            endedAt: DateTime(2026, 5, 2, 10),
            durationSeconds: 40 * 60,
          ),
          ReportFocusRecord(
            endedAt: DateTime(2026, 5, 3, 10),
            durationSeconds: 60 * 60,
          ),
        ],
      );

      expect(result.points.map((point) => point.label), ['5/1', '5/2', '5/3']);
      expect(result.points.map((point) => point.diaryEntries), [1, 2, 3]);
      expect(result.points.map((point) => point.focusMinutes), [20, 40, 60]);
      expect(result.pearson, closeTo(1, 0.001));
      expect(result.maxDiaryEntries, 3);
      expect(result.maxFocusMinutes, 60);
    });

    test('top-level build includes diary focus correlation', () {
      final result = ReportCrossAnalysis.build(
        start: DateTime(2026, 5, 1),
        end: DateTime(2026, 5, 2),
        bucket: ReportCrossBucket.day,
        todoCompletions: const [],
        focusSessions: [
          ReportCrossFocusSession(
            endedAt: DateTime(2026, 5, 1, 22),
            durationSeconds: 25 * 60,
          ),
          ReportCrossFocusSession(
            endedAt: DateTime(2026, 5, 2, 22),
            durationSeconds: 50 * 60,
          ),
        ],
        diaryEntries: [
          ReportCrossDiaryEntry(DateTime(2026, 5, 1, 21)),
          ReportCrossDiaryEntry(DateTime(2026, 5, 2, 21)),
          ReportCrossDiaryEntry(DateTime(2026, 5, 2, 22)),
        ],
        timeEntries: const [],
      );

      expect(result.diaryFocus.points.map((point) => point.diaryEntries), [
        1,
        2,
      ]);
      expect(result.diaryFocus.points.map((point) => point.focusMinutes), [
        25,
        50,
      ]);
      expect(result.diaryFocus.pearson, closeTo(1, 0.001));
    });
  });

  group('ReportCrossAnalysis time category share trend', () {
    test('builds monthly share buckets and ranks top categories', () {
      final work = Object();
      final study = Object();
      final life = Object();

      final result = ReportCrossAnalysis.buildTimeCategoryShareTrend(
        start: DateTime(2026, 1, 15),
        end: DateTime(2026, 3, 3),
        bucket: ReportCrossAnalysisBucket.month,
        records: [
          ReportTimeCategoryRecord(
            startAt: DateTime(2026, 1, 20),
            durationSeconds: 60 * 60,
            category: work,
          ),
          ReportTimeCategoryRecord(
            startAt: DateTime(2026, 1, 21),
            durationSeconds: 30 * 60,
            category: study,
          ),
          ReportTimeCategoryRecord(
            startAt: DateTime(2026, 2, 1),
            durationSeconds: 90 * 60,
            category: study,
          ),
          ReportTimeCategoryRecord(
            startAt: DateTime(2026, 3, 1),
            durationSeconds: 30 * 60,
            category: life,
          ),
          ReportTimeCategoryRecord(
            startAt: DateTime(2026, 1, 1),
            durationSeconds: 999,
            category: life,
          ),
        ],
      );

      expect(result.buckets.map((bucket) => bucket.label), ['1月', '2月', '3月']);
      expect(result.buckets.first.start, DateTime(2026, 1, 15));
      expect(result.buckets.last.end, DateTime(2026, 3, 3));
      expect(result.categories.take(3), [study, work, life]);
      expect(result.buckets[0].shareFor(work), closeTo(2 / 3, 0.001));
      expect(result.buckets[0].shareFor(study), closeTo(1 / 3, 0.001));
      expect(result.buckets[1].shareFor(study), 1);
      expect(result.buckets[2].shareFor(life), 1);
    });

    test('limits category count', () {
      final categories = List.generate(6, (_) => Object());

      final result = ReportCrossAnalysis.buildTimeCategoryShareTrend(
        start: DateTime(2026, 5, 1),
        end: DateTime(2026, 5, 1),
        bucket: ReportCrossAnalysisBucket.day,
        categoryLimit: 4,
        records: [
          for (final (index, category) in categories.indexed)
            ReportTimeCategoryRecord(
              startAt: DateTime(2026, 5, 1, 8 + index),
              durationSeconds: (index + 1) * 60,
              category: category,
            ),
        ],
      );

      expect(result.categories.length, 4);
      expect(result.categories.first, categories.last);
    });
  });

  group('ReportCrossAnalysis time output efficiency trend', () {
    test('builds daily time and completed todo output points', () {
      final result = ReportCrossAnalysis.buildTimeOutputEfficiencyTrend(
        start: DateTime(2026, 5, 1),
        end: DateTime(2026, 5, 2),
        bucket: ReportCrossAnalysisBucket.day,
        completions: [
          ReportCompletionRecord(completedAt: DateTime(2026, 5, 1, 9)),
          ReportCompletionRecord(completedAt: DateTime(2026, 5, 1, 10)),
          ReportCompletionRecord(completedAt: DateTime(2026, 5, 1, 11)),
          ReportCompletionRecord(completedAt: DateTime(2026, 5, 1, 12)),
          ReportCompletionRecord(completedAt: DateTime(2026, 5, 2, 9)),
          ReportCompletionRecord(completedAt: DateTime(2026, 5, 3, 9)),
        ],
        records: [
          ReportTimeCategoryRecord(
            startAt: DateTime(2026, 5, 1, 8),
            durationSeconds: 90 * 60,
            category: 'work',
          ),
          ReportTimeCategoryRecord(
            startAt: DateTime(2026, 5, 1, 14),
            durationSeconds: 30 * 60,
            category: 'study',
          ),
          ReportTimeCategoryRecord(
            startAt: DateTime(2026, 5, 1, 16),
            durationSeconds: -30 * 60,
            category: 'ignored',
          ),
          ReportTimeCategoryRecord(
            startAt: DateTime(2026, 5, 2, 8),
            durationSeconds: 60 * 60,
            category: 'work',
          ),
          ReportTimeCategoryRecord(
            startAt: DateTime(2026, 5, 3, 8),
            durationSeconds: 600 * 60,
            category: 'ignored',
          ),
        ],
      );

      expect(result.points.map((point) => point.label), ['5/1', '5/2']);
      expect(result.points.map((point) => point.timeMinutes), [120, 60]);
      expect(result.points.map((point) => point.completedTodos), [4, 1]);
      expect(result.points[0].completedTodosPerHour, closeTo(2, 0.001));
      expect(result.points[1].completedTodosPerHour, closeTo(1, 0.001));
      expect(result.maxTimeMinutes, 120);
      expect(result.maxCompletedTodos, 4);
      expect(result.maxCompletedTodosPerHour, closeTo(2, 0.001));
    });

    test('top-level build includes time output efficiency', () {
      final result = ReportCrossAnalysis.build(
        start: DateTime(2026, 5, 1),
        end: DateTime(2026, 5, 2),
        bucket: ReportCrossBucket.day,
        todoCompletions: [
          ReportCrossTodoCompletion(DateTime(2026, 5, 1, 12)),
          ReportCrossTodoCompletion(DateTime(2026, 5, 1, 13)),
          ReportCrossTodoCompletion(DateTime(2026, 5, 2, 12)),
        ],
        focusSessions: const [],
        timeEntries: [
          ReportCrossTimeEntry(
            startedAt: DateTime(2026, 5, 1, 8),
            durationSeconds: 60 * 60,
            categoryKey: 'work',
          ),
          ReportCrossTimeEntry(
            startedAt: DateTime(2026, 5, 2, 8),
            durationSeconds: 30 * 60,
            categoryKey: 'life',
          ),
        ],
      );

      expect(result.timeOutputEfficiency.points.map((point) => point.label), [
        '5/1',
        '5/2',
      ]);
      expect(
        result.timeOutputEfficiency.points.map((point) => point.timeMinutes),
        [60, 30],
      );
      expect(
        result.timeOutputEfficiency.points.map((point) => point.completedTodos),
        [2, 1],
      );
      expect(
        result.timeOutputEfficiency.points[0].completedTodosPerHour,
        closeTo(2, 0.001),
      );
      expect(
        result.timeOutputEfficiency.points[1].completedTodosPerHour,
        closeTo(2, 0.001),
      );
    });
  });
}
