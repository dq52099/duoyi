import 'package:flutter_test/flutter_test.dart';

import 'package:duoyi/models/anniversary.dart';
import 'package:duoyi/models/goal.dart';
import 'package:duoyi/models/habit.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/services/reminder_scheduler.dart';
import 'package:duoyi/services/reminder_sinks.dart';

class _FakeNotifSink implements ReminderNotificationSink {
  final List<Map<String, Object?>> scheduled = [];
  final List<int> cancelled = [];
  final List<String> cancelledHabits = [];
  final List<String> cancelledTodos = [];
  final List<String> cancelledAnniversaries = [];

  @override
  Future<void> scheduleOnce({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
  }) async {
    scheduled.add({
      'kind': 'once',
      'id': id,
      'title': title,
      'when': when,
      'payload': payload,
    });
  }

  @override
  Future<void> scheduleDaily({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    List<int>? weekdays,
    String? payload,
  }) async {
    scheduled.add({'kind': 'daily', 'id': id, 'hour': hour, 'minute': minute});
  }

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
  }

  @override
  Future<void> cancelTodoReminder(String todoId) async {
    cancelledTodos.add(todoId);
  }

  @override
  Future<void> cancelHabitReminder(String habitId) async {
    cancelledHabits.add(habitId);
  }

  @override
  Future<void> cancelAnniversary(String annId) async {
    cancelledAnniversaries.add(annId);
  }

  @override
  Future<void> scheduleHabitReminder({
    required String habitId,
    required String habitName,
    required int hour,
    required int minute,
    List<int>? weekdays,
  }) async {
    scheduled.add({
      'kind': 'habit',
      'habitId': habitId,
      'hour': hour,
      'minute': minute,
    });
  }

  @override
  Future<void> scheduleAnniversary({
    required String annId,
    required String title,
    required DateTime whenDate,
    int daysBefore = 1,
    int hour = 9,
    int minute = 0,
  }) async {
    scheduled.add({
      'kind': 'anniversary_push',
      'id': annId,
      'whenDate': whenDate,
      'daysBefore': daysBefore,
    });
  }
}

class _FakeAlarmSink implements ReminderAlarmSink {
  final List<Map<String, Object?>> scheduled = [];
  final List<int> cancelled = [];

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
  }

  @override
  Future<void> scheduleFullScreen({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
    bool requireExactAlarm = true,
    bool fullScreen = true,
    bool vibrate = true,
    int snoozeMinutes = 0,
    int repeatCount = 0,
  }) async {
    scheduled.add({
      'kind': 'fullscreen',
      'id': id,
      'when': when,
      'payload': payload,
      'vibrate': vibrate,
      'snoozeMinutes': snoozeMinutes,
      'repeatCount': repeatCount,
    });
  }

  @override
  Future<void> scheduleDailyFullScreen({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    List<int>? weekdays,
    String? payload,
    bool requireExactAlarm = true,
    bool fullScreen = true,
    bool vibrate = true,
    int snoozeMinutes = 0,
    int repeatCount = 0,
  }) async {
    scheduled.add({
      'kind': 'daily_fullscreen',
      'id': id,
      'hour': hour,
      'minute': minute,
      'vibrate': vibrate,
      'snoozeMinutes': snoozeMinutes,
      'repeatCount': repeatCount,
    });
  }
}

void main() {
  late _FakeNotifSink notif;
  late _FakeAlarmSink alarm;
  late ReminderScheduler scheduler;

  setUp(() {
    notif = _FakeNotifSink();
    alarm = _FakeAlarmSink();
    scheduler = ReminderScheduler(notif, alarm: alarm);
  });

  group('ReminderScheduler 集成', () {
    test('syncTodos 对已完成待办不调度', () async {
      final completed = TodoItem(
        id: 't1',
        title: '已完成',
        date: DateTime(2026, 5, 14),
        isCompleted: true,
      );
      await scheduler.syncTodos([completed]);
      expect(notif.scheduled, isEmpty);
      expect(alarm.scheduled, isEmpty);
    });

    test('syncHabits 把启用提醒的习惯调度成 daily full-screen', () async {
      final habit = Habit(
        id: 'h1',
        name: '阅读',
        remind: true,
        remindHour: 21,
        remindMinute: 30,
      );
      await scheduler.syncHabits([habit]);
      expect(alarm.scheduled.length, 1);
      expect(alarm.scheduled.first['kind'], 'daily_fullscreen');
      expect(alarm.scheduled.first['hour'], 21);
      expect(alarm.scheduled.first['minute'], 30);
    });

    test('syncHabits 关闭提醒后清理上一轮调度', () async {
      final h1 = Habit(
        id: 'h1',
        name: '阅读',
        remind: true,
        remindHour: 9,
        remindMinute: 0,
      );
      await scheduler.syncHabits([h1]);
      expect(alarm.scheduled.length, 1);
      final h1Off = Habit(id: 'h1', name: '阅读', remind: false);
      await scheduler.syncHabits([h1Off]);
      // 第二轮再写入是空集
      expect(notif.cancelledHabits, contains('h1'));
    });

    test('syncAnniversaries 默认走 push 通道', () async {
      final a = Anniversary(
        title: '生日',
        originDate: DateTime(2027, 6, 1),
        type: AnniversaryType.birthday,
        remind: true,
        remindDaysBefore: 1,
        remindHour: 9,
        reminderKind: ReminderKind.push,
      );
      await scheduler.syncAnniversaries([a]);
      expect(notif.scheduled.length, 1);
      expect(notif.scheduled.first['kind'], 'anniversary_push');
    });

    test('syncAnniversaries kind=alarm 走全屏闹钟', () async {
      final a = Anniversary(
        title: '重要纪念',
        originDate: DateTime(2027, 6, 1),
        type: AnniversaryType.memorial,
        remind: true,
        remindDaysBefore: 1,
        remindHour: 9,
        reminderKind: ReminderKind.alarm,
      );
      await scheduler.syncAnniversaries([a]);
      expect(alarm.scheduled.length, 1);
      expect(alarm.scheduled.first['kind'], 'fullscreen');
      expect(alarm.scheduled.first['payload'], 'duoyi://anniversary/${a.id}');
    });

    test('syncGoals 对非 active 状态不调度', () async {
      final g = GoalItem(id: 'g1', title: '已完成目标', status: GoalStatus.achieved);
      await scheduler.syncGoals([g]);
      expect(notif.scheduled, isEmpty);
      expect(alarm.scheduled, isEmpty);
    });
  });
}
