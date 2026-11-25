import 'package:test/test.dart';

import 'package:duoyi/core/todo_filters.dart';

enum _Quadrant { q1 }

enum _Priority { normal }

class _Todo {
  final String id;
  final bool completed;
  final bool archived;

  const _Todo(this.id, {this.completed = false, this.archived = false});
}

void main() {
  group('effectiveTodoFilter', () {
    const allTodos = TodoFilterState<_Quadrant, _Priority>();

    test('all shows completed by default and hides them when disabled', () {
      expect(
        effectiveTodoFilter(allTodos).completion,
        TodoCompletionFilter.all,
      );
      expect(
        effectiveTodoFilter(allTodos, showCompletedTodos: true).completion,
        TodoCompletionFilter.all,
      );
      expect(
        effectiveTodoFilter(allTodos, showCompletedTodos: false).completion,
        TodoCompletionFilter.active,
      );
    });

    test('explicit active and Completed filters are kept as selected', () {
      for (final completion in [
        TodoCompletionFilter.active,
        TodoCompletionFilter.completed,
      ]) {
        final explicitFilter = allTodos.copyWith(completion: completion);

        for (final showCompletedTodos in [false, true]) {
          final effective = effectiveTodoFilter(
            explicitFilter,
            showCompletedTodos: showCompletedTodos,
          );
          expect(effective.completion, completion);
          expect(
            _filterIds(const [
              _Todo('active'),
              _Todo('completed', completed: true),
            ], effective),
            completion == TodoCompletionFilter.active
                ? ['active']
                : ['completed'],
          );
        }
      }
    });

    test('the explicit Archived entry keeps all completion states visible', () {
      const archivedEntry = TodoFilterState<_Quadrant, _Priority>(
        includeArchived: true,
      );
      final effective = effectiveTodoFilter(
        archivedEntry,
        showCompletedTodos: false,
      );
      const todos = [
        _Todo('active'),
        _Todo('completed', completed: true),
        _Todo('archived', completed: true, archived: true),
      ];

      expect(effective.completion, TodoCompletionFilter.all);
      expect(effective.includeArchived, isTrue);
      expect(_filterIds(todos, effective), ['active', 'completed', 'archived']);
    });

    test(
      'Today overview keeps completed items visible when the setting is off',
      () {
        const todayOverview = TodoFilterState<_Quadrant, _Priority>(
          todayOverview: true,
        );
        final effective = effectiveTodoFilter(
          todayOverview,
          showCompletedTodos: false,
        );

        expect(effective.completion, TodoCompletionFilter.all);
        expect(
          _filterIds(
            const [_Todo('completed', completed: true)],
            effective,
            isInTodayOverview: (_, _) => true,
          ),
          ['completed'],
        );
      },
    );
  });
}

List<String> _filterIds(
  Iterable<_Todo> todos,
  TodoFilterState<_Quadrant, _Priority> filter, {
  bool Function(_Todo todo, DateTime reference)? isInTodayOverview,
}) => filterTodos(
  todos,
  filter,
  quadrantOf: (_) => _Quadrant.q1,
  priorityOf: (_) => _Priority.normal,
  tagsOf: (_) => const <String>[],
  listGroupNameOf: (_) => null,
  dueDateOf: (_) => null,
  isCompletedOf: (todo) => todo.completed,
  isArchivedAfterRolloverOf: (todo) => todo.archived,
  isInTodayOverviewOf: isInTodayOverview,
).map((todo) => todo.id).toList();
