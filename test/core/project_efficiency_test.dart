import 'package:duoyi/core/project_efficiency.dart';
import 'package:test/test.dart';

void main() {
  group('ProjectEfficiencyAnalyzer', () {
    test('aggregates completed todos, goal milestones, and positive time', () {
      final breakdown = ProjectEfficiencyAnalyzer.build(
        todoCompletions: [
          _todo('alpha', 'Alpha'),
          _todo('alpha', 'Alpha'),
          _todo('beta', 'Beta'),
        ],
        goalCompletions: [
          _goal('alpha', 'Alpha'),
          _goal('beta', 'Beta'),
          _goal('beta', 'Beta'),
        ],
        timeAllocations: const [
          ProjectEfficiencyTimeAllocation(
            projectKey: 'alpha',
            projectLabel: 'Alpha',
            durationSeconds: 30 * 60,
          ),
          ProjectEfficiencyTimeAllocation(
            projectKey: 'alpha',
            projectLabel: 'Alpha',
            durationSeconds: -10 * 60,
          ),
          ProjectEfficiencyTimeAllocation(
            projectKey: 'beta',
            projectLabel: 'Beta',
            durationSeconds: 60 * 60,
          ),
          ProjectEfficiencyTimeAllocation(
            projectKey: 'ignored',
            projectLabel: 'Ignored',
            durationSeconds: 0,
          ),
        ],
      );

      final byKey = {for (final item in breakdown.items) item.projectKey: item};

      expect(byKey.keys, unorderedEquals(['alpha', 'beta']));

      final alpha = byKey['alpha']!;
      expect(alpha.completedTodos, 2);
      expect(alpha.completedGoalSteps, 1);
      expect(alpha.outputCount, 3);
      expect(alpha.timeSeconds, 30 * 60);
      expect(alpha.timeMinutes, 30);
      expect(alpha.outputPerHour, closeTo(6, 0.001));

      final beta = byKey['beta']!;
      expect(beta.completedTodos, 1);
      expect(beta.completedGoalSteps, 2);
      expect(beta.outputCount, 3);
      expect(beta.timeSeconds, 60 * 60);
      expect(beta.outputPerHour, closeTo(3, 0.001));
    });

    test('ranks by output per hour, output count, time, then label', () {
      final breakdown = ProjectEfficiencyAnalyzer.build(
        todoCompletions: [
          _todo('rate', 'Rate first'),
          _todo('bravo', 'Bravo'),
          _todo('bravo', 'Bravo'),
          _todo('alpha', 'Alpha'),
        ],
        goalCompletions: const [],
        timeAllocations: const [
          ProjectEfficiencyTimeAllocation(
            projectKey: 'rate',
            projectLabel: 'Rate first',
            durationSeconds: 5 * 60,
          ),
          ProjectEfficiencyTimeAllocation(
            projectKey: 'bravo',
            projectLabel: 'Bravo',
            durationSeconds: 20 * 60,
          ),
          ProjectEfficiencyTimeAllocation(
            projectKey: 'alpha',
            projectLabel: 'Alpha',
            durationSeconds: 10 * 60,
          ),
          ProjectEfficiencyTimeAllocation(
            projectKey: 'delta',
            projectLabel: 'Delta',
            durationSeconds: 60 * 60,
          ),
          ProjectEfficiencyTimeAllocation(
            projectKey: 'echo',
            projectLabel: 'Echo',
            durationSeconds: 15 * 60,
          ),
          ProjectEfficiencyTimeAllocation(
            projectKey: 'foxtrot',
            projectLabel: 'Foxtrot',
            durationSeconds: 15 * 60,
          ),
        ],
      );

      expect(breakdown.rankedItems.map((item) => item.projectKey), [
        'rate',
        'bravo',
        'alpha',
        'delta',
        'echo',
        'foxtrot',
      ]);
    });

    test('applies the limit after ranking', () {
      final breakdown = ProjectEfficiencyAnalyzer.build(
        todoCompletions: [
          _todo('steady', 'Steady'),
          _todo('fast', 'Fast'),
          _todo('fast', 'Fast'),
          _todo('slow', 'Slow'),
        ],
        goalCompletions: [_goal('fast', 'Fast'), _goal('steady', 'Steady')],
        timeAllocations: const [
          ProjectEfficiencyTimeAllocation(
            projectKey: 'fast',
            projectLabel: 'Fast',
            durationSeconds: 30 * 60,
          ),
          ProjectEfficiencyTimeAllocation(
            projectKey: 'steady',
            projectLabel: 'Steady',
            durationSeconds: 45 * 60,
          ),
          ProjectEfficiencyTimeAllocation(
            projectKey: 'slow',
            projectLabel: 'Slow',
            durationSeconds: 120 * 60,
          ),
        ],
        limit: 2,
      );

      expect(breakdown.items, hasLength(2));
      expect(breakdown.items.map((item) => item.projectKey), [
        'fast',
        'steady',
      ]);
    });
  });
}

ProjectEfficiencyTodoCompletion _todo(String key, String label) {
  return ProjectEfficiencyTodoCompletion(
    completedAt: DateTime(2026, 5, 21, 10),
    projectKey: key,
    projectLabel: label,
  );
}

ProjectEfficiencyGoalCompletion _goal(String key, String label) {
  return ProjectEfficiencyGoalCompletion(
    completedAt: DateTime(2026, 5, 21, 11),
    projectKey: key,
    projectLabel: label,
  );
}
