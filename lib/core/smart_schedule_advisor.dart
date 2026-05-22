import '../models/todo.dart';

class SmartScheduleSuggestion {
  final TodoItem todo;
  final String reason;
  final int score;

  const SmartScheduleSuggestion({
    required this.todo,
    required this.reason,
    required this.score,
  });
}

class SmartScheduleAdvisor {
  SmartScheduleAdvisor._();

  static List<SmartScheduleSuggestion> suggestToday(
    Iterable<TodoItem> todos, {
    DateTime? now,
    int limit = 5,
  }) {
    final base = now ?? DateTime.now();
    final today = DateTime(base.year, base.month, base.day);
    final tomorrow = today.add(const Duration(days: 1));
    final candidates = <SmartScheduleSuggestion>[];

    for (final todo in todos) {
      if (todo.isCompleted || todo.isArchivedAfterRollover) continue;
      final suggestion = _score(todo, base, today, tomorrow);
      if (suggestion != null) candidates.add(suggestion);
    }

    candidates.sort((a, b) {
      final score = b.score.compareTo(a.score);
      if (score != 0) return score;
      final dueA = a.todo.dueDate;
      final dueB = b.todo.dueDate;
      if (dueA != null && dueB != null) return dueA.compareTo(dueB);
      if (dueA != null) return -1;
      if (dueB != null) return 1;
      final priority = b.todo.priority.rank.compareTo(a.todo.priority.rank);
      if (priority != 0) return priority;
      return a.todo.createdAt.compareTo(b.todo.createdAt);
    });

    return candidates.take(limit).toList(growable: false);
  }

  static SmartScheduleSuggestion? _score(
    TodoItem todo,
    DateTime now,
    DateTime today,
    DateTime tomorrow,
  ) {
    var score = 0;
    final reasons = <String>[];

    final due = todo.dueDate;
    if (due != null) {
      if (due.isBefore(now)) {
        score += 120;
        reasons.add('已逾期');
      } else if (due.isBefore(now.add(const Duration(hours: 3)))) {
        score += 100;
        reasons.add('3 小时内到期');
      } else if (due.isBefore(tomorrow)) {
        score += 80;
        reasons.add('今天到期');
      } else if (due.isBefore(tomorrow.add(const Duration(days: 1)))) {
        score += 48;
        reasons.add('明天到期');
      }
    }

    final dateDay = DateTime(todo.date.year, todo.date.month, todo.date.day);
    if (dateDay == today) {
      score += 34;
      reasons.add('计划今天处理');
    } else if (dateDay.isBefore(today)) {
      score += 28;
      reasons.add('计划日期已过');
    } else if (dateDay == tomorrow) {
      score += 10;
      reasons.add('明天计划');
    }

    score += switch (todo.priority) {
      TodoPriority.urgent => 36,
      TodoPriority.high => 28,
      TodoPriority.medium => 16,
      TodoPriority.low => 8,
      TodoPriority.none => 0,
    };
    if (todo.priority == TodoPriority.urgent) {
      reasons.add('紧急优先级');
    } else if (todo.priority == TodoPriority.high) {
      reasons.add('高优先级');
    }

    score += switch (todo.quadrant) {
      EisenhowerQuadrant.urgentImportant => 30,
      EisenhowerQuadrant.notUrgentImportant => 18,
      EisenhowerQuadrant.urgentNotImportant => 12,
      EisenhowerQuadrant.notUrgentNotImportant => 0,
    };
    if (todo.quadrant == EisenhowerQuadrant.urgentImportant) {
      reasons.add('重要且紧急');
    } else if (todo.quadrant == EisenhowerQuadrant.notUrgentImportant) {
      reasons.add('重要任务');
    }

    if (score < 34) return null;

    final uniqueReasons = <String>[];
    for (final reason in reasons) {
      if (!uniqueReasons.contains(reason)) uniqueReasons.add(reason);
    }
    return SmartScheduleSuggestion(
      todo: todo,
      reason: uniqueReasons.take(3).join(' · '),
      score: score,
    );
  }
}
