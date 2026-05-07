import '../models/habit.dart';
import '../models/todo.dart';
import '../models/anniversary.dart';
import '../providers/notification_service.dart';

/// 根据 todo/habit/anniversary 数据幂等地同步本地通知队列。
///
/// 每次数据变化时由 main.dart 调用 [sync]。服务内部负责：
/// 1. 先取消自己管理过的 id；
/// 2. 再按最新数据重新 schedule。
class ReminderScheduler {
  final NotificationService notif;
  final Set<String> _scheduledTodoIds = {};
  final Set<String> _scheduledHabitIds = {};
  final Set<String> _scheduledAnniIds = {};

  ReminderScheduler(this.notif);

  /// 重新同步 todo 提醒；带 reminderAt 且未完成的未来待办会被调度。
  Future<void> syncTodos(Iterable<TodoItem> todos) async {
    final wanted = <String, TodoItem>{};
    for (final t in todos) {
      if (t.isCompleted) continue;
      if (!t.hasReminder) continue;
      final when = t.reminderAt ?? t.dueDate;
      if (when == null) continue;
      if (when.isBefore(DateTime.now())) continue;
      wanted[t.id] = t;
    }
    // 取消已移除/过期/关闭提醒的
    for (final id in _scheduledTodoIds.difference(wanted.keys.toSet())) {
      await notif.cancelTodoReminder(id);
    }
    // 重新调度
    for (final t in wanted.values) {
      await notif.scheduleTodoReminder(
        todoId: t.id,
        title: t.title,
        when: t.reminderAt ?? t.dueDate!,
      );
    }
    _scheduledTodoIds
      ..clear()
      ..addAll(wanted.keys);
  }

  Future<void> syncHabits(Iterable<Habit> habits) async {
    final wanted = <String, Habit>{};
    for (final h in habits) {
      if (!h.remind) continue;
      if (h.remindHour == null || h.remindMinute == null) continue;
      wanted[h.id] = h;
    }
    for (final id in _scheduledHabitIds.difference(wanted.keys.toSet())) {
      await notif.cancelHabitReminder(id);
    }
    for (final h in wanted.values) {
      // activeWeekdays 是 0..6(周一=0)，转换到 flutter_local_notifications 的
      // 1..7(周一=1..周日=7)
      final weekdays = h.activeWeekdays.map((w) => w + 1).toList();
      await notif.scheduleHabitReminder(
        habitId: h.id,
        habitName: h.name,
        hour: h.remindHour!,
        minute: h.remindMinute!,
        weekdays: weekdays.isEmpty ? null : weekdays,
      );
    }
    _scheduledHabitIds
      ..clear()
      ..addAll(wanted.keys);
  }

  Future<void> syncAnniversaries(Iterable<Anniversary> items) async {
    final wanted = <String, Anniversary>{};
    for (final a in items) {
      if (!a.remind) continue;
      final nextDate = a.nextOccurrence;
      if (nextDate.isBefore(DateTime.now().subtract(const Duration(days: 1)))) {
        continue;
      }
      wanted[a.id] = a;
    }
    for (final id in _scheduledAnniIds.difference(wanted.keys.toSet())) {
      await notif.cancelAnniversary(id);
    }
    for (final a in wanted.values) {
      await notif.scheduleAnniversary(
        annId: a.id,
        title: a.title,
        whenDate: a.nextOccurrence,
        daysBefore: a.remindDaysBefore,
      );
    }
    _scheduledAnniIds
      ..clear()
      ..addAll(wanted.keys);
  }
}
