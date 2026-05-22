import 'package:test/test.dart';

import 'package:duoyi/core/todo_filters.dart';

enum FakeQuadrant { q1, q2, q3, q4 }

enum FakePriority { none, low, medium, high }

class FakeTodo {
  final String id;
  final FakeQuadrant quadrant;
  final FakePriority priority;
  final String? listGroupName;
  final List<String> tags;
  final DateTime? dueDate;
  final bool isCompleted;
  final bool isArchivedAfterRollover;

  const FakeTodo({
    required this.id,
    required this.quadrant,
    required this.priority,
    this.listGroupName,
    this.tags = const [],
    this.dueDate,
    this.isCompleted = false,
    this.isArchivedAfterRollover = false,
  });
}

void main() {
  group('Todo filters', () {
    final now = DateTime(2026, 5, 19, 12);

    List<FakeTodo> sampleTodos() => [
      FakeTodo(
        id: 'today-work',
        quadrant: FakeQuadrant.q1,
        priority: FakePriority.high,
        listGroupName: '工作',
        tags: ['work', 'focus'],
        dueDate: DateTime(2026, 5, 19, 18),
      ),
      FakeTodo(
        id: 'overdue-home',
        quadrant: FakeQuadrant.q2,
        priority: FakePriority.low,
        listGroupName: '生活',
        tags: ['home'],
        dueDate: DateTime(2026, 5, 18, 9),
      ),
      const FakeTodo(
        id: 'completed-free',
        quadrant: FakeQuadrant.q4,
        priority: FakePriority.none,
        tags: ['archive'],
        isCompleted: true,
      ),
      FakeTodo(
        id: 'next-week',
        quadrant: FakeQuadrant.q3,
        priority: FakePriority.medium,
        listGroupName: '生活',
        tags: ['home', 'errand'],
        dueDate: DateTime(2026, 5, 25),
      ),
      FakeTodo(
        id: 'archived-today',
        quadrant: FakeQuadrant.q1,
        priority: FakePriority.high,
        listGroupName: '工作',
        tags: ['work'],
        dueDate: DateTime(2026, 5, 19, 8),
        isArchivedAfterRollover: true,
      ),
    ];

    List<FakeTodo> runFilter(
      Iterable<FakeTodo> todos,
      TodoFilterState<FakeQuadrant, FakePriority> filter,
    ) {
      return filterTodos(
        todos,
        filter,
        now: now,
        quadrantOf: (todo) => todo.quadrant,
        priorityOf: (todo) => todo.priority,
        tagsOf: (todo) => todo.tags,
        listGroupNameOf: (todo) => todo.listGroupName,
        dueDateOf: (todo) => todo.dueDate,
        isCompletedOf: (todo) => todo.isCompleted,
        isArchivedAfterRolloverOf: (todo) => todo.isArchivedAfterRollover,
      );
    }

    test('matches combined quadrant priority tag list and due filters', () {
      final result = runFilter(
        sampleTodos(),
        const TodoFilterState(
          quadrant: FakeQuadrant.q1,
          priority: FakePriority.high,
          tag: 'work',
          listGroupName: '工作',
          due: TodoDueFilter.dueToday,
          completion: TodoCompletionFilter.active,
        ),
      );

      expect(result.map((todo) => todo.id), ['today-work']);
    });

    test('filters due states with stable date boundaries', () {
      final todos = sampleTodos();

      expect(
        runFilter(
          todos,
          const TodoFilterState(due: TodoDueFilter.overdue),
        ).map((todo) => todo.id),
        ['overdue-home'],
      );
      expect(
        runFilter(
          todos,
          const TodoFilterState(due: TodoDueFilter.dueToday),
        ).map((todo) => todo.id),
        ['today-work'],
      );
      expect(
        runFilter(
          todos,
          const TodoFilterState(due: TodoDueFilter.next7Days),
        ).map((todo) => todo.id),
        ['today-work', 'next-week'],
      );
      expect(
        runFilter(
          todos,
          const TodoFilterState(due: TodoDueFilter.noDue),
        ).map((todo) => todo.id),
        ['completed-free'],
      );
    });

    test('filters completion state and hides archived items by default', () {
      final todos = sampleTodos();

      expect(
        runFilter(
          todos,
          const TodoFilterState(completion: TodoCompletionFilter.active),
        ).map((todo) => todo.id),
        ['today-work', 'overdue-home', 'next-week'],
      );
      expect(
        runFilter(
          todos,
          const TodoFilterState(completion: TodoCompletionFilter.completed),
        ).map((todo) => todo.id),
        ['completed-free'],
      );
      expect(
        runFilter(
          todos,
          const TodoFilterState(
            due: TodoDueFilter.dueToday,
            includeArchived: true,
          ),
        ).map((todo) => todo.id),
        ['today-work', 'archived-today'],
      );
    });

    test(
      'groups filtered todos and exposes available tags and list groups',
      () {
        final todos = sampleTodos();
        final filtered = runFilter(todos, const TodoFilterState(tag: 'home'));
        final quadrantGroups = groupTodosByQuadrant(
          filtered,
          quadrants: FakeQuadrant.values,
          quadrantOf: (todo) => todo.quadrant,
        );
        final listGroups = groupTodosByList(
          todos,
          (todo) => todo.listGroupName,
        );

        expect(quadrantGroups, contains(FakeQuadrant.q1));
        expect(quadrantGroups[FakeQuadrant.q2]!.map((todo) => todo.id), [
          'overdue-home',
        ]);
        expect(quadrantGroups[FakeQuadrant.q3]!.map((todo) => todo.id), [
          'next-week',
        ]);
        expect(
          listGroups.keys,
          containsAll(['工作', '生活', ungroupedTodoListName]),
        );
        expect(collectTodoTags(todos, (todo) => todo.tags), [
          'archive',
          'errand',
          'focus',
          'home',
          'work',
        ]);
        expect(collectTodoListGroups(todos, (todo) => todo.listGroupName), [
          '工作',
          '未分组',
          '生活',
        ]);
      },
    );

    test('copyWith supports clearing nullable filters', () {
      const initial = TodoFilterState<FakeQuadrant, FakePriority>(
        quadrant: FakeQuadrant.q1,
        priority: FakePriority.high,
        tag: ' work ',
        listGroupName: ' 工作 ',
        due: TodoDueFilter.dueToday,
        completion: TodoCompletionFilter.active,
      );

      final normalized = initial.copyWith(tag: ' work ', listGroupName: ' 工作 ');
      expect(normalized.tag, 'work');
      expect(normalized.listGroupName, '工作');
      expect(normalized.hasActiveFilters, isTrue);

      final cleared = normalized.copyWith(
        quadrant: null,
        priority: null,
        tag: '',
        listGroupName: null,
        due: TodoDueFilter.all,
        completion: TodoCompletionFilter.all,
      );

      expect(cleared.hasActiveFilters, isFalse);
    });
  });
}
