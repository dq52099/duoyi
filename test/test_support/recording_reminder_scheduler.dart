import 'package:duoyi/models/anniversary.dart';
import 'package:duoyi/models/countdown.dart';
import 'package:duoyi/models/goal.dart';
import 'package:duoyi/models/habit.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/services/reminder_scheduler.dart';
import 'package:duoyi/services/reminder_sinks.dart';

class RecordingReminderScheduler extends ReminderScheduler {
  RecordingReminderScheduler() : super(_NoopReminderNotificationSink());

  final List<List<String>> habitSyncs = [];
  final List<List<String>> todoSyncs = [];
  final List<List<String>> countdownSyncs = [];
  final List<List<String>> anniversarySyncs = [];
  final List<List<String>> goalSyncs = [];
  Object? todoSyncError;

  @override
  Future<void> syncTodos(
    Iterable<TodoItem> todos, {
    bool allowJustMissedOneShotReminders = true,
  }) async {
    if (todoSyncError != null) throw todoSyncError!;
    todoSyncs.add(todos.map((todo) => todo.id).toList(growable: false));
  }

  @override
  Future<void> syncHabits(Iterable<Habit> habits) async {
    habitSyncs.add(habits.map((habit) => habit.id).toList(growable: false));
  }

  @override
  Future<void> syncCountdowns(Iterable<CountdownItem> items) async {
    countdownSyncs.add(items.map((item) => item.id).toList(growable: false));
  }

  @override
  Future<void> syncAnniversaries(Iterable<Anniversary> items) async {
    anniversarySyncs.add(items.map((item) => item.id).toList(growable: false));
  }

  @override
  Future<void> syncGoals(Iterable<GoalItem> goals) async {
    goalSyncs.add(goals.map((goal) => goal.id).toList(growable: false));
  }
}

class _NoopReminderNotificationSink implements ReminderNotificationSink {
  @override
  Future<void> cancel(int id) async {}

  @override
  Future<void> cancelAnniversary(String annId) async {}

  @override
  Future<void> cancelHabitReminder(String habitId) async {}

  @override
  Future<void> cancelTodoReminder(String todoId) async {}

  @override
  Future<void> scheduleAnniversary({
    required String annId,
    required String title,
    required DateTime whenDate,
    int daysBefore = 1,
    int hour = 9,
    int minute = 0,
  }) async {}

  @override
  Future<void> scheduleDaily({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    List<int>? weekdays,
    String? payload,
  }) async {}

  @override
  Future<void> scheduleHabitReminder({
    required String habitId,
    required String habitName,
    required int hour,
    required int minute,
    List<int>? weekdays,
  }) async {}

  @override
  Future<void> scheduleOnce({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
  }) async {}
}
