const Object _unset = Object();
const String ungroupedTodoListName = '未分组';

enum TodoDueFilter { all, overdue, dueToday, next7Days, noDue }

enum TodoCompletionFilter { all, active, completed }

enum TodoSortOrder { manual, dueDate, priority, created }

class TodoFilterState<Q, P> {
  final Q? quadrant;
  final P? priority;
  final String? tag;
  final String? listGroupName;
  final TodoDueFilter due;
  final TodoCompletionFilter completion;
  final bool includeArchived;
  final bool todayOverview;
  final String query;
  final TodoSortOrder sortOrder;

  const TodoFilterState({
    this.quadrant,
    this.priority,
    this.tag,
    this.listGroupName,
    this.due = TodoDueFilter.all,
    this.completion = TodoCompletionFilter.all,
    this.includeArchived = false,
    this.todayOverview = false,
    this.query = '',
    this.sortOrder = TodoSortOrder.manual,
  });

  bool get hasActiveFilters =>
      quadrant != null ||
      priority != null ||
      tag != null ||
      listGroupName != null ||
      due != TodoDueFilter.all ||
      completion != TodoCompletionFilter.all ||
      includeArchived ||
      todayOverview ||
      query.trim().isNotEmpty ||
      sortOrder != TodoSortOrder.manual;

  TodoFilterState<Q, P> copyWith({
    Object? quadrant = _unset,
    Object? priority = _unset,
    Object? tag = _unset,
    Object? listGroupName = _unset,
    TodoDueFilter? due,
    TodoCompletionFilter? completion,
    bool? includeArchived,
    bool? todayOverview,
    String? query,
    TodoSortOrder? sortOrder,
  }) {
    return TodoFilterState<Q, P>(
      quadrant: identical(quadrant, _unset) ? this.quadrant : quadrant as Q?,
      priority: identical(priority, _unset) ? this.priority : priority as P?,
      tag: identical(tag, _unset) ? this.tag : _normalizedFilterText(tag),
      listGroupName: identical(listGroupName, _unset)
          ? this.listGroupName
          : _normalizedFilterText(listGroupName),
      due: due ?? this.due,
      completion: completion ?? this.completion,
      includeArchived: includeArchived ?? this.includeArchived,
      todayOverview: todayOverview ?? this.todayOverview,
      query: query ?? this.query,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }
}

/// Apply the default list preference without changing an explicit history view.
TodoFilterState<Q, P> effectiveTodoFilter<Q, P>(
  TodoFilterState<Q, P> filter, {
  bool showCompletedTodos = true,
}) {
  if (showCompletedTodos ||
      filter.completion != TodoCompletionFilter.all ||
      filter.includeArchived ||
      filter.todayOverview) {
    return filter;
  }
  return filter.copyWith(completion: TodoCompletionFilter.active);
}

List<T> filterTodos<T, Q, P>(
  Iterable<T> todos,
  TodoFilterState<Q, P> filter, {
  DateTime? now,
  required Q Function(T todo) quadrantOf,
  required P Function(T todo) priorityOf,
  required Iterable<String> Function(T todo) tagsOf,
  required String? Function(T todo) listGroupNameOf,
  required DateTime? Function(T todo) dueDateOf,
  required bool Function(T todo) isCompletedOf,
  required bool Function(T todo) isArchivedAfterRolloverOf,
  bool Function(T todo, DateTime reference)? isInTodayOverviewOf,
  String Function(T todo)? titleOf,
  String Function(T todo)? notesOf,
}) {
  final reference = now ?? DateTime.now();
  final today = _dateOnly(reference);
  final next7Days = today.add(const Duration(days: 6));
  final normalizedQuery = filter.query.trim().toLowerCase();

  return todos.where((todo) {
    if (!filter.includeArchived && isArchivedAfterRolloverOf(todo)) {
      return false;
    }
    if (filter.todayOverview &&
        isInTodayOverviewOf?.call(todo, reference) != true) {
      return false;
    }

    switch (filter.completion) {
      case TodoCompletionFilter.all:
        break;
      case TodoCompletionFilter.active:
        if (isCompletedOf(todo)) return false;
        break;
      case TodoCompletionFilter.completed:
        if (!isCompletedOf(todo)) return false;
        break;
    }

    final quadrant = filter.quadrant;
    if (quadrant != null && quadrantOf(todo) != quadrant) return false;

    final priority = filter.priority;
    if (priority != null && priorityOf(todo) != priority) return false;

    final tag = filter.tag;
    if (tag != null && !tagsOf(todo).contains(tag)) return false;

    final listGroupName = filter.listGroupName;
    if (listGroupName != null &&
        todoListGroupName(listGroupNameOf(todo)) != listGroupName) {
      return false;
    }

    if (normalizedQuery.isNotEmpty) {
      final title = (titleOf?.call(todo) ?? '').toLowerCase();
      final notes = (notesOf?.call(todo) ?? '').toLowerCase();
      final listName = todoListGroupName(listGroupNameOf(todo)).toLowerCase();
      final hasTagMatch = tagsOf(todo).any(
        (t) => t.toLowerCase().contains(normalizedQuery),
      );
      if (!title.contains(normalizedQuery) &&
          !notes.contains(normalizedQuery) &&
          !listName.contains(normalizedQuery) &&
          !hasTagMatch) {
        return false;
      }
    }

    final due = dueDateOf(todo);
    switch (filter.due) {
      case TodoDueFilter.all:
        return true;
      case TodoDueFilter.overdue:
        return due != null && !isCompletedOf(todo) && due.isBefore(reference);
      case TodoDueFilter.dueToday:
        return due != null && _dateOnly(due) == today;
      case TodoDueFilter.next7Days:
        if (due == null) return false;
        final dueDay = _dateOnly(due);
        return !dueDay.isBefore(today) && !dueDay.isAfter(next7Days);
      case TodoDueFilter.noDue:
        return due == null;
    }
  }).toList();
}

List<T> sortTodos<T>(
  Iterable<T> todos,
  TodoSortOrder sortOrder, {
  required DateTime? Function(T todo) dueDateOf,
  required int Function(T todo) priorityRankOf,
  required DateTime Function(T todo) createdAtOf,
  required int Function(T todo) sortOrderOf,
  bool Function(T todo)? isCompletedOf,
}) {
  final result = todos.toList();
  if (sortOrder == TodoSortOrder.manual || result.length < 2) {
    return result;
  }
  final originalIndex = <int, int>{
    for (var i = 0; i < result.length; i++) i: i,
  };
  final indexed = List<int>.generate(result.length, (i) => i);
  indexed.sort((ia, ib) {
    final a = result[ia];
    final b = result[ib];
    if (isCompletedOf != null) {
      final ca = isCompletedOf(a);
      final cb = isCompletedOf(b);
      if (ca != cb) return ca ? 1 : -1;
    }
    switch (sortOrder) {
      case TodoSortOrder.manual:
        final orderCmp = sortOrderOf(a).compareTo(sortOrderOf(b));
        return orderCmp != 0
            ? orderCmp
            : originalIndex[ia]!.compareTo(originalIndex[ib]!);
      case TodoSortOrder.dueDate:
        final da = dueDateOf(a);
        final db = dueDateOf(b);
        if (da != null && db != null) {
          final cmp = da.compareTo(db);
          if (cmp != 0) return cmp;
        } else if (da != null) {
          return -1;
        } else if (db != null) {
          return 1;
        }
        final prioCmp = priorityRankOf(b).compareTo(priorityRankOf(a));
        if (prioCmp != 0) return prioCmp;
        final manualCmp = sortOrderOf(a).compareTo(sortOrderOf(b));
        return manualCmp != 0
            ? manualCmp
            : originalIndex[ia]!.compareTo(originalIndex[ib]!);
      case TodoSortOrder.priority:
        final prioCmp = priorityRankOf(b).compareTo(priorityRankOf(a));
        if (prioCmp != 0) return prioCmp;
        final da = dueDateOf(a);
        final db = dueDateOf(b);
        if (da != null && db != null) {
          final cmp = da.compareTo(db);
          if (cmp != 0) return cmp;
        } else if (da != null) {
          return -1;
        } else if (db != null) {
          return 1;
        }
        final manualCmp = sortOrderOf(a).compareTo(sortOrderOf(b));
        return manualCmp != 0
            ? manualCmp
            : originalIndex[ia]!.compareTo(originalIndex[ib]!);
      case TodoSortOrder.created:
        final cmp = createdAtOf(b).compareTo(createdAtOf(a));
        if (cmp != 0) return cmp;
        final manualCmp = sortOrderOf(a).compareTo(sortOrderOf(b));
        return manualCmp != 0
            ? manualCmp
            : originalIndex[ia]!.compareTo(originalIndex[ib]!);
    }
  });
  return [for (final idx in indexed) result[idx]];
}

Map<Q, List<T>> groupTodosByQuadrant<T, Q>(
  Iterable<T> todos, {
  required Iterable<Q> quadrants,
  required Q Function(T todo) quadrantOf,
}) {
  final groups = <Q, List<T>>{};
  for (final quadrant in quadrants) {
    groups[quadrant] = <T>[];
  }
  for (final todo in todos) {
    groups.putIfAbsent(quadrantOf(todo), () => <T>[]).add(todo);
  }
  return groups;
}

Map<String, List<T>> groupTodosByList<T>(
  Iterable<T> todos,
  String? Function(T todo) listGroupNameOf,
) {
  final groups = <String, List<T>>{};
  for (final todo in todos) {
    groups
        .putIfAbsent(todoListGroupName(listGroupNameOf(todo)), () => <T>[])
        .add(todo);
  }
  return groups;
}

List<String> collectTodoTags<T>(
  Iterable<T> todos,
  Iterable<String> Function(T todo) tagsOf,
) {
  final tags = <String>{};
  for (final todo in todos) {
    for (final tag in tagsOf(todo)) {
      final normalized = _normalizedFilterText(tag);
      if (normalized != null) tags.add(normalized);
    }
  }
  return tags.toList()..sort();
}

List<String> collectTodoListGroups<T>(
  Iterable<T> todos,
  String? Function(T todo) listGroupNameOf,
) {
  final groups = <String>{};
  for (final todo in todos) {
    groups.add(todoListGroupName(listGroupNameOf(todo)));
  }
  return groups.toList()..sort();
}

String todoListGroupName(String? listGroupName) {
  final name = listGroupName?.trim();
  if (name == null || name.isEmpty) return ungroupedTodoListName;
  return name;
}

String? _normalizedFilterText(Object? value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) return null;
  return text;
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);
