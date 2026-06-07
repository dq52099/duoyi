import 'dart:async';

import 'package:test/test.dart';

import 'package:duoyi/models/anniversary.dart';
import 'package:duoyi/models/countdown.dart';
import 'package:duoyi/models/goal.dart';
import 'package:duoyi/models/habit.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/services/alarm_service.dart';
import 'package:duoyi/services/notification_permission_exception.dart';
import 'package:duoyi/services/reminder_scheduler.dart';
import 'package:duoyi/services/reminder_sinks.dart';

class _FakeNotifSink
    implements
        ReminderNotificationSink,
        ReminderPendingSink,
        ReminderScheduleIssueSink {
  final List<Map<String, Object?>> scheduled = [];
  final List<int> cancelled = [];
  final List<String> cancelledHabits = [];
  final List<String> cancelledTodos = [];
  final List<String> cancelledAnniversaries = [];
  final List<Map<String, Object?>> issues = [];
  final Set<int> pending = {};
  bool denyScheduleOnce = false;
  bool denyScheduleDaily = false;
  bool failScheduleOnceGeneric = false;
  bool failScheduleDailyGeneric = false;
  bool denyHabitReminder = false;
  bool denyAnniversary = false;
  bool failCancel = false;
  bool failCancelAnniversary = false;
  bool failPendingIds = false;
  Future<void>? scheduleOnceGate;

  @override
  Future<void> scheduleOnce({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
  }) async {
    await scheduleOnceGate;
    if (denyScheduleOnce) {
      throw const NotificationPermissionDeniedException();
    }
    if (failScheduleOnceGeneric) {
      throw StateError('forced scheduleOnce plugin failure');
    }
    scheduled.add({
      'kind': 'once',
      'id': id,
      'title': title,
      'body': body,
      'when': when,
      'payload': payload,
    });
    pending.add(id);
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
    if (denyScheduleDaily) {
      throw const NotificationPermissionDeniedException();
    }
    if (failScheduleDailyGeneric) {
      throw StateError('forced scheduleDaily plugin failure');
    }
    scheduled.add({
      'kind': 'daily',
      'id': id,
      'title': title,
      'body': body,
      'hour': hour,
      'minute': minute,
      'payload': payload,
    });
    _rememberPendingRepeating(id, weekdays);
  }

  @override
  Future<void> cancel(int id) async {
    if (failCancel) {
      throw StateError('forced notification cancel failure');
    }
    cancelled.add(id);
    pending.remove(id);
    for (var weekday = 1; weekday <= 7; weekday += 1) {
      pending.remove(_subId(id, weekday));
      pending.remove(_legacySubId(id, weekday));
    }
  }

  @override
  Future<List<int>> pendingIds() async {
    if (failPendingIds) {
      throw StateError('forced notification pending query failure');
    }
    return pending.toList()..sort();
  }

  void _rememberPendingRepeating(int id, List<int>? weekdays) {
    if (weekdays == null || weekdays.isEmpty) {
      pending.add(id);
      return;
    }
    for (final weekday in weekdays) {
      pending.add(_subId(id, weekday));
    }
  }

  @override
  Future<void> cancelTodoReminder(String todoId) async {
    cancelledTodos.add(todoId);
  }

  @override
  Future<void> cancelHabitReminder(String habitId) async {
    cancelledHabits.add(habitId);
    final id = _idFor('habit_$habitId');
    pending.remove(id);
    for (var weekday = 1; weekday <= 7; weekday += 1) {
      pending.remove(_subId(id, weekday));
      pending.remove(_legacySubId(id, weekday));
    }
  }

  @override
  Future<void> cancelAnniversary(String annId) async {
    if (failCancelAnniversary) {
      throw StateError('forced anniversary cancel failure');
    }
    cancelledAnniversaries.add(annId);
    pending.remove(_idFor('anni_$annId'));
  }

  @override
  Future<void> scheduleHabitReminder({
    required String habitId,
    required String habitName,
    required int hour,
    required int minute,
    List<int>? weekdays,
  }) async {
    if (denyHabitReminder) {
      throw const NotificationPermissionDeniedException();
    }
    scheduled.add({
      'kind': 'habit',
      'habitId': habitId,
      'title': '习惯打卡提醒',
      'body': '别忘了: $habitName',
      'hour': hour,
      'minute': minute,
    });
    _rememberPendingRepeating(_idFor('habit_$habitId'), weekdays);
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
    if (denyAnniversary) {
      throw const NotificationPermissionDeniedException();
    }
    scheduled.add({
      'kind': 'anniversary_push',
      'id': annId,
      'whenDate': whenDate,
      'daysBefore': daysBefore,
    });
    pending.add(_idFor('anni_$annId'));
  }

  @override
  void recordReminderScheduleIssue({
    required String title,
    required String message,
    DateTime? scheduledTime,
    String? relatedId,
    bool blocking = true,
  }) {
    issues.add({
      'title': title,
      'message': message,
      'scheduledTime': scheduledTime,
      'relatedId': relatedId,
      'blocking': blocking,
    });
  }
}

class _FakeAlarmSink implements ReminderAlarmSink, ReminderPendingSink {
  final List<Map<String, Object?>> scheduled = [];
  final List<int> cancelled = [];
  final Set<int> pending = {};
  bool failFullScreenWithAlarmPermission = false;
  bool failFullScreenWithNotificationPermission = false;
  bool failFullScreenWithGenericError = false;
  bool rememberFullScreenPendingBeforeGenericError = false;
  bool rememberFullScreenPendingBeforeAlarmPermission = false;
  bool rememberFullScreenPendingBeforeNotificationPermission = false;
  bool failFullScreenWithHandoff = false;
  bool failDailyWithAlarmPermission = false;
  bool failDailyWithNotificationPermission = false;
  bool failDailyWithGenericError = false;
  bool rememberDailyPendingBeforeGenericError = false;
  bool rememberDailyPendingBeforeAlarmPermission = false;
  bool rememberDailyPendingBeforeNotificationPermission = false;
  bool failDailyWithHandoff = false;
  bool failCancel = false;
  bool failPendingIds = false;

  @override
  Future<void> cancel(int id) async {
    if (failCancel) {
      throw StateError('forced alarm cancel failure');
    }
    cancelled.add(id);
    pending.remove(id);
    for (var weekday = 1; weekday <= 7; weekday += 1) {
      pending.remove(_subId(id, weekday));
      pending.remove(_legacySubId(id, weekday));
    }
  }

  @override
  Future<List<int>> pendingIds() async {
    if (failPendingIds) {
      throw StateError('forced pending query failure');
    }
    return pending.toList()..sort();
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
    if (failFullScreenWithAlarmPermission) {
      if (rememberFullScreenPendingBeforeAlarmPermission) {
        pending.add(id);
      }
      throw AlarmPermissionDeniedException('forced full-screen failure');
    }
    if (failFullScreenWithNotificationPermission) {
      if (rememberFullScreenPendingBeforeNotificationPermission) {
        pending.add(id);
      }
      throw const NotificationPermissionDeniedException();
    }
    if (failFullScreenWithGenericError) {
      if (rememberFullScreenPendingBeforeGenericError) {
        pending.add(id);
      }
      throw StateError('forced full-screen plugin failure');
    }
    if (failFullScreenWithHandoff) {
      throw AlarmQueueHandoffException('forced full-screen handoff failure');
    }
    scheduled.add({
      'kind': 'fullscreen',
      'id': id,
      'title': title,
      'body': body,
      'when': when,
      'payload': payload,
      'vibrate': vibrate,
      'snoozeMinutes': snoozeMinutes,
      'repeatCount': repeatCount,
    });
    pending.add(id);
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
    if (failDailyWithAlarmPermission) {
      if (rememberDailyPendingBeforeAlarmPermission) {
        _rememberPendingRepeating(id, weekdays);
      }
      throw AlarmPermissionDeniedException('forced daily alarm failure');
    }
    if (failDailyWithNotificationPermission) {
      if (rememberDailyPendingBeforeNotificationPermission) {
        _rememberPendingRepeating(id, weekdays);
      }
      throw NotificationPermissionDeniedException();
    }
    if (failDailyWithGenericError) {
      if (rememberDailyPendingBeforeGenericError) {
        _rememberPendingRepeating(id, weekdays);
      }
      throw StateError('forced daily full-screen plugin failure');
    }
    if (failDailyWithHandoff) {
      throw AlarmQueueHandoffException('forced daily handoff failure');
    }
    scheduled.add({
      'kind': 'daily_fullscreen',
      'id': id,
      'title': title,
      'body': body,
      'payload': payload,
      'hour': hour,
      'minute': minute,
      'fullScreen': fullScreen,
      'vibrate': vibrate,
      'snoozeMinutes': snoozeMinutes,
      'repeatCount': repeatCount,
    });
    if (weekdays == null || weekdays.isEmpty) {
      pending.add(id);
    } else {
      for (final weekday in weekdays) {
        pending.add(_subId(id, weekday));
      }
    }
  }

  void _rememberPendingRepeating(int id, List<int>? weekdays) {
    if (weekdays == null || weekdays.isEmpty) {
      pending.add(id);
      return;
    }
    for (final weekday in weekdays) {
      pending.add(_subId(id, weekday));
    }
  }
}

class _FakePopupSink implements ReminderPopupSink {
  final List<Map<String, Object?>> scheduled = [];
  final List<int> cancelled = [];
  bool failOnce = false;
  bool failRepeating = false;
  bool failCancel = false;

  @override
  Future<void> cancel(int id) async {
    if (failCancel) {
      throw StateError('forced popup cancel failure');
    }
    cancelled.add(id);
  }

  @override
  Future<void> scheduleOnce({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
  }) async {
    if (failOnce) {
      throw StateError('forced popup fallback failure');
    }
    scheduled.add({
      'kind': 'popup_once',
      'id': id,
      'title': title,
      'when': when,
      'payload': payload,
    });
  }

  @override
  Future<void> scheduleRepeating({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    List<int>? weekdays,
    String? payload,
  }) async {
    if (failRepeating) {
      throw StateError('forced repeating popup fallback failure');
    }
    scheduled.add({
      'kind': 'popup_repeating',
      'id': id,
      'title': title,
      'body': body,
      'hour': hour,
      'minute': minute,
      'payload': payload,
    });
  }
}

class _FakeEmailSink implements ReminderEmailSink {
  final List<Map<String, Object?>> scheduled = [];
  final List<int> cancelled = [];
  bool failOnce = false;
  bool failRepeating = false;
  bool failCancel = false;

  @override
  Future<void> cancel(int id) async {
    if (failCancel) {
      throw StateError('forced email cancel failure');
    }
    cancelled.add(id);
  }

  @override
  Future<void> scheduleOnce({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
  }) async {
    if (failOnce) {
      throw StateError('forced email once failure');
    }
    scheduled.add({
      'kind': 'email_once',
      'id': id,
      'title': title,
      'when': when,
      'payload': payload,
    });
  }

  @override
  Future<void> scheduleRepeating({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    List<int>? weekdays,
    String? payload,
  }) async {
    if (failRepeating) {
      throw StateError('forced email repeating failure');
    }
    scheduled.add({
      'kind': 'email_repeating',
      'id': id,
      'title': title,
      'body': body,
      'hour': hour,
      'minute': minute,
      'payload': payload,
    });
  }
}

int _idFor(String key) {
  int h = 0;
  for (final c in key.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return h;
}

int _subId(int base, int weekday) {
  var h = 0x811c9dc5;
  final key = '$base:$weekday';
  for (final unit in key.codeUnits) {
    h ^= unit;
    h = (h * 0x01000193) & 0x7fffffff;
  }
  return h == 0 ? weekday : h;
}

int _legacySubId(int base, int weekday) => base * 10 + weekday;

int _anniversaryAlarmId(String annId) => _idFor('anni_alarm_$annId');
int _anniversaryPopupId(String annId) => _idFor('anni_$annId');

void main() {
  late _FakeNotifSink notif;
  late _FakeAlarmSink alarm;
  late _FakePopupSink popup;
  late _FakeEmailSink email;
  late InMemoryReminderScheduleRegistry registry;
  late ReminderScheduler scheduler;

  setUp(() {
    notif = _FakeNotifSink();
    alarm = _FakeAlarmSink();
    popup = _FakePopupSink();
    email = _FakeEmailSink();
    registry = InMemoryReminderScheduleRegistry();
    scheduler = ReminderScheduler(
      notif,
      alarm: alarm,
      popup: popup,
      email: email,
      registry: registry,
    );
  });

  group('ReminderScheduler 集成', () {
    test('preflight blocks enabled one-shot todo reminders in the past', () {
      final now = DateTime(2026, 5, 24, 10);
      final todo = TodoItem(
        id: 'past-reminder',
        title: '过期提醒',
        dueDate: DateTime(2026, 5, 24),
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'r1',
              type: ReminderRuleType.absolute,
              kind: ReminderKind.push,
              hour: 9,
              minute: 30,
            ),
          ],
        ),
      );

      final result = preflightTodoReminderPlan(todo, now: now);

      expect(result.hasEnabledPlan, isTrue);
      expect(result.ok, isFalse);
      expect(result.blockingIssue?.message, contains('提醒时间已过去'));
      expect(result.firstScheduledTime, isNull);
    });

    test('preflight accepts just-missed same-minute one-shot reminders', () {
      final now = DateTime(2026, 5, 24, 10, 40, 35);
      final todo = TodoItem(
        id: 'same-minute-reminder',
        title: '刚创建的同分钟提醒',
        dueDate: DateTime(2026, 5, 24),
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'r1',
              type: ReminderRuleType.absolute,
              kind: ReminderKind.push,
              hour: 10,
              minute: 40,
            ),
          ],
        ),
      );

      final result = preflightTodoReminderPlan(todo, now: now);

      expect(result.ok, isTrue);
      expect(
        result.firstScheduledTime,
        DateTime(
          now.year,
          now.month,
          now.day,
          now.hour,
          now.minute,
        ).add(const Duration(minutes: 1)),
      );
      expect(result.blockingIssue, isNull);
    });

    test(
      'startup resync does not re-arm just-missed same-minute one-shot reminders',
      () async {
        final now = DateTime.now();
        final sameMinute = DateTime(
          now.year,
          now.month,
          now.day,
          now.hour,
          now.minute,
        );
        final todo = TodoItem(
          id: 'startup-same-minute-reminder',
          title: '更新后不要立刻提醒',
          dueDate: sameMinute,
          reminderPlan: ReminderPlan(
            enabled: true,
            rules: [
              ReminderRule(
                id: 'r1',
                type: ReminderRuleType.absolute,
                kind: ReminderKind.push,
                hour: sameMinute.hour,
                minute: sameMinute.minute,
              ),
            ],
          ),
        );

        await scheduler.syncTodos([
          todo,
        ], allowJustMissedOneShotReminders: false);

        expect(notif.scheduled, isEmpty);
        expect(notif.pending, isEmpty);
      },
    );

    test(
      'write-side sync still accepts just-missed same-minute one-shot reminders',
      () async {
        final now = DateTime.now();
        final sameMinute = DateTime(
          now.year,
          now.month,
          now.day,
          now.hour,
          now.minute,
        );
        final todo = TodoItem(
          id: 'write-side-same-minute-reminder',
          title: '刚保存的同分钟提醒',
          dueDate: sameMinute,
          reminderPlan: ReminderPlan(
            enabled: true,
            rules: [
              ReminderRule(
                id: 'r1',
                type: ReminderRuleType.absolute,
                kind: ReminderKind.push,
                hour: sameMinute.hour,
                minute: sameMinute.minute,
              ),
            ],
          ),
        );

        await scheduler.syncTodos([todo]);

        expect(notif.scheduled, hasLength(1));
        expect(
          notif.scheduled.single['when'],
          sameMinute.add(const Duration(minutes: 1)),
        );
      },
    );

    test(
      'syncTodos records visible issue when enabled reminder resolves empty',
      () async {
        final past = DateTime.now().subtract(const Duration(days: 1));
        final todo = TodoItem(
          id: 'past-sync-reminder',
          title: '已错过提醒',
          dueDate: past,
          reminderPlan: ReminderPlan(
            enabled: true,
            rules: [
              ReminderRule(
                id: 'r1',
                type: ReminderRuleType.absolute,
                kind: ReminderKind.push,
                hour: past.hour,
                minute: past.minute,
              ),
            ],
          ),
        );

        await scheduler.syncTodos([todo]);

        expect(notif.scheduled, isEmpty);
        expect(notif.issues, hasLength(1));
        expect(notif.issues.single['relatedId'], todo.id);
        expect(notif.issues.single['title'], '待办提醒注册失败');
        expect(notif.issues.single['message'], contains('提醒时间已过去'));
      },
    );

    test('syncTodos 并发触发时串行化，避免同一提醒重复下发', () async {
      final gate = Completer<void>();
      notif.scheduleOnceGate = gate.future;
      final due = DateTime.now().add(const Duration(hours: 2));
      final todo = TodoItem(
        id: 'concurrent-sync',
        title: '并发提醒',
        dueDate: due,
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'r1',
              type: ReminderRuleType.absolute,
              kind: ReminderKind.push,
              hour: due.hour,
              minute: due.minute,
            ),
          ],
        ),
      );

      final first = scheduler.syncTodos([todo]);
      final second = scheduler.syncTodos([todo]);

      await Future<void>.delayed(Duration.zero);
      expect(notif.scheduled, isEmpty);
      gate.complete();
      await Future.wait([first, second]);

      expect(notif.scheduled, hasLength(1));
      expect(notif.scheduled.single['id'], _idFor('todo:${todo.id}:r1'));
    });

    test('syncTodos 对完全相同的多条规则只下发一次', () async {
      final due = DateTime.now().add(const Duration(hours: 2));
      final todo = TodoItem(
        id: 'duplicate-rules',
        title: '重复规则提醒',
        dueDate: due,
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'first',
              type: ReminderRuleType.absolute,
              kind: ReminderKind.push,
              hour: due.hour,
              minute: due.minute,
            ),
            ReminderRule(
              id: 'second',
              type: ReminderRuleType.absolute,
              kind: ReminderKind.push,
              hour: due.hour,
              minute: due.minute,
            ),
          ],
        ),
      );

      await scheduler.syncTodos([todo]);

      expect(notif.scheduled.map((entry) => entry['id']), [
        _idFor('todo:${todo.id}:first'),
      ]);
      expect(alarm.scheduled, isEmpty);
      expect(popup.scheduled, isEmpty);
    });

    test('syncTodos 对同一时间同一内容的不同规则类型只下发一次', () async {
      final due = DateTime.now().add(const Duration(hours: 2));
      final todo = TodoItem(
        id: 'duplicate-delivery-rules',
        title: '重复投递提醒',
        dueDate: due,
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'absolute',
              type: ReminderRuleType.absolute,
              kind: ReminderKind.push,
              hour: due.hour,
              minute: due.minute,
            ),
            ReminderRule(
              id: 'relative',
              type: ReminderRuleType.relativeToDue,
              kind: ReminderKind.push,
              hour: due.hour,
              minute: due.minute,
              offsetMinutes: 0,
            ),
          ],
        ),
      );

      await scheduler.syncTodos([todo]);

      expect(notif.scheduled.map((entry) => entry['id']), [
        _idFor('todo:${todo.id}:absolute'),
      ]);
      expect(notif.scheduled.single['title'], '提醒：${todo.title}');
    });

    test('syncTodos 对重复的每日通知只注册第一条规则', () async {
      final todo = TodoItem(
        id: 'duplicate-daily-push',
        title: '重复每日通知',
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'first-daily',
              type: ReminderRuleType.dailyTime,
              kind: ReminderKind.push,
              hour: 9,
              minute: 15,
            ),
            ReminderRule(
              id: 'second-daily',
              type: ReminderRuleType.dailyTime,
              kind: ReminderKind.push,
              hour: 9,
              minute: 15,
            ),
          ],
        ),
      );
      final firstId = _idFor('todo:${todo.id}:first-daily');
      final secondId = _idFor('todo:${todo.id}:second-daily');

      await scheduler.syncTodos([todo]);

      expect(notif.scheduled.map((entry) => entry['id']), [firstId]);
      expect(notif.scheduled.single['title'], '今日提醒');
      expect(notif.scheduled.single['body'], todo.title);
      expect(notif.pending, contains(firstId));
      expect(notif.pending, isNot(contains(secondId)));
      expect(alarm.scheduled, isEmpty);
      expect(popup.scheduled, isEmpty);
    });

    test('syncTodos 同一时间同时配置通知和闹钟时只保留闹钟', () async {
      final due = DateTime.now().add(const Duration(hours: 2));
      final todo = TodoItem(
        id: 'duplicate-kind-delivery',
        title: '同一时间双通道',
        dueDate: due,
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'push-rule',
              type: ReminderRuleType.absolute,
              kind: ReminderKind.push,
              hour: due.hour,
              minute: due.minute,
            ),
            ReminderRule(
              id: 'alarm-rule',
              type: ReminderRuleType.relativeToDue,
              kind: ReminderKind.alarm,
              hour: due.hour,
              minute: due.minute,
              offsetMinutes: 0,
              fullScreen: true,
            ),
          ],
        ),
      );

      await scheduler.syncTodos([todo]);

      expect(notif.scheduled, isEmpty);
      expect(alarm.scheduled.map((entry) => entry['id']), [
        _idFor('todo:${todo.id}:alarm-rule'),
      ]);
      expect(
        alarm.scheduled.single['payload'],
        'duoyi://todo/${todo.id}?confirm=1',
      );
    });

    test('syncTodos 同一时间同时配置通知和弹出框时只保留通知', () async {
      final due = DateTime.now().add(const Duration(hours: 2));
      final todo = TodoItem(
        id: 'duplicate-push-popup-delivery',
        title: '同一时间通知弹窗',
        dueDate: due,
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'popup-rule',
              type: ReminderRuleType.absolute,
              kind: ReminderKind.popup,
              hour: due.hour,
              minute: due.minute,
            ),
            ReminderRule(
              id: 'push-rule',
              type: ReminderRuleType.relativeToDue,
              kind: ReminderKind.push,
              hour: due.hour,
              minute: due.minute,
              offsetMinutes: 0,
            ),
          ],
        ),
      );

      await scheduler.syncTodos([todo]);

      expect(notif.scheduled.map((entry) => entry['id']), [
        _idFor('todo:${todo.id}:push-rule'),
      ]);
      expect(popup.scheduled, isEmpty);
      expect(alarm.scheduled, isEmpty);
    });

    test('syncTodos 同一时间同时配置弹出框和闹钟时只保留闹钟', () async {
      final due = DateTime.now().add(const Duration(hours: 2));
      final todo = TodoItem(
        id: 'duplicate-popup-alarm-delivery',
        title: '同一时间弹窗闹钟',
        dueDate: due,
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'popup-rule',
              type: ReminderRuleType.absolute,
              kind: ReminderKind.popup,
              hour: due.hour,
              minute: due.minute,
            ),
            ReminderRule(
              id: 'alarm-rule',
              type: ReminderRuleType.relativeToDue,
              kind: ReminderKind.alarm,
              hour: due.hour,
              minute: due.minute,
              offsetMinutes: 0,
              fullScreen: true,
            ),
          ],
        ),
      );

      await scheduler.syncTodos([todo]);

      expect(notif.scheduled, isEmpty);
      expect(popup.scheduled, isEmpty);
      expect(alarm.scheduled.map((entry) => entry['id']), [
        _idFor('todo:${todo.id}:alarm-rule'),
      ]);
    });

    test('syncTodos 每周部分重叠时只替换冲突日期', () async {
      final todo = TodoItem(
        id: 'weekly-overlap-kind-delivery',
        title: '每周重叠双通道',
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'push-weekly',
              type: ReminderRuleType.weeklyTime,
              kind: ReminderKind.push,
              hour: 8,
              minute: 30,
              weekdays: const [1, 3],
            ),
            ReminderRule(
              id: 'alarm-weekly',
              type: ReminderRuleType.weeklyTime,
              kind: ReminderKind.alarm,
              hour: 8,
              minute: 30,
              weekdays: const [3, 5],
            ),
          ],
        ),
      );
      final pushId = _idFor('todo:${todo.id}:push-weekly');
      final alarmId = _idFor('todo:${todo.id}:alarm-weekly');

      await scheduler.syncTodos([todo]);

      expect(notif.scheduled.map((entry) => entry['id']), [pushId]);
      expect(alarm.scheduled.map((entry) => entry['id']), [alarmId]);
      expect(notif.pending, contains(_subId(pushId, 1)));
      expect(notif.pending, isNot(contains(_subId(pushId, 3))));
      expect(
        alarm.pending,
        containsAll([_subId(alarmId, 3), _subId(alarmId, 5)]),
      );
    });

    test('syncTodos 每日和每周全选同时间只保留更高优先级', () async {
      final todo = TodoItem(
        id: 'daily-weekly-overlap-kind-delivery',
        title: '每日每周重叠',
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'push-daily',
              type: ReminderRuleType.dailyTime,
              kind: ReminderKind.push,
              hour: 9,
              minute: 0,
            ),
            ReminderRule(
              id: 'alarm-weekly-all',
              type: ReminderRuleType.weeklyTime,
              kind: ReminderKind.alarm,
              hour: 9,
              minute: 0,
              weekdays: const [1, 2, 3, 4, 5, 6, 7],
            ),
          ],
        ),
      );

      await scheduler.syncTodos([todo]);

      expect(notif.scheduled, isEmpty);
      expect(alarm.scheduled.map((entry) => entry['id']), [
        _idFor('todo:${todo.id}:alarm-weekly-all'),
      ]);
    });

    test('syncTodos 不合并不同时间的提醒规则', () async {
      final due = DateTime.now().add(const Duration(hours: 3));
      final first = due.minute == 59
          ? DateTime(due.year, due.month, due.day, due.hour + 1)
          : DateTime(due.year, due.month, due.day, due.hour, due.minute + 1);
      final todo = TodoItem(
        id: 'distinct-rules',
        title: '多时间提醒',
        dueDate: due,
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'first',
              type: ReminderRuleType.absolute,
              kind: ReminderKind.push,
              hour: due.hour,
              minute: due.minute,
            ),
            ReminderRule(
              id: 'second',
              type: ReminderRuleType.absolute,
              kind: ReminderKind.push,
              hour: first.hour,
              minute: first.minute,
            ),
          ],
        ),
      );

      await scheduler.syncTodos([todo]);

      expect(notif.scheduled.map((entry) => entry['id']), [
        _idFor('todo:${todo.id}:first'),
        _idFor('todo:${todo.id}:second'),
      ]);
    });

    test('syncTodos 刚错过同一分钟不会因秒级漂移重复下发', () async {
      var now = DateTime.now();
      if (now.second > 50) {
        await Future<void>.delayed(Duration(seconds: 61 - now.second));
        now = DateTime.now();
      }
      final due = DateTime(now.year, now.month, now.day, now.hour, now.minute);
      final todo = TodoItem(
        id: 'same-minute-drift',
        title: '同分钟提醒',
        dueDate: due,
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'r1',
              type: ReminderRuleType.absolute,
              kind: ReminderKind.push,
              hour: due.hour,
              minute: due.minute,
            ),
          ],
        ),
      );

      await scheduler.syncTodos([todo]);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await scheduler.syncTodos([todo]);

      expect(notif.scheduled, hasLength(1));
      expect(
        (notif.scheduled.single['when'] as DateTime).second,
        0,
        reason: '同分钟兜底时间要固定到下一分钟起点，避免连续同步时指纹漂移。',
      );
    });

    test(
      'syncTodos does not record issue when reminders are disabled',
      () async {
        final todo = TodoItem(
          id: 'disabled-reminder',
          title: '未开启提醒',
          reminderPlan: const ReminderPlan.disabled(),
        );

        await scheduler.syncTodos([todo]);

        expect(notif.scheduled, isEmpty);
        expect(notif.issues, isEmpty);
      },
    );

    test(
      'preflight accepts future one-shot todo reminders and reports kind',
      () {
        final now = DateTime(2026, 5, 24, 10);
        final todo = TodoItem(
          id: 'future-reminder',
          title: '未来提醒',
          dueDate: DateTime(2026, 5, 24),
          reminderPlan: ReminderPlan(
            enabled: true,
            rules: [
              ReminderRule(
                id: 'r1',
                type: ReminderRuleType.absolute,
                kind: ReminderKind.alarm,
                hour: 10,
                minute: 30,
                fullScreen: true,
              ),
            ],
          ),
        );

        final result = preflightTodoReminderPlan(todo, now: now);

        expect(result.ok, isTrue);
        expect(result.kinds, contains(ReminderKind.alarm));
        expect(result.firstScheduledTime, DateTime(2026, 5, 24, 10, 30));
      },
    );

    test('preflight blocks relative reminders without an anchor date', () {
      final todo = TodoItem(
        id: 'missing-anchor',
        title: '缺少日期',
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'r1',
              type: ReminderRuleType.relativeToDue,
              kind: ReminderKind.push,
              hour: 9,
              minute: 0,
              offsetMinutes: -15,
            ),
          ],
        ),
      );

      final result = preflightTodoReminderPlan(
        todo,
        now: DateTime(2026, 5, 24, 10),
      );

      expect(result.ok, isFalse);
      expect(result.blockingIssue?.message, contains('截止日期'));
    });

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

    test('syncHabits 把启用提醒的习惯优先调度成闹钟提醒', () async {
      final habit = Habit(
        id: 'h1',
        name: '阅读',
        remind: true,
        remindHour: 21,
        remindMinute: 30,
      );
      await scheduler.syncHabits([habit]);
      expect(notif.scheduled, isEmpty);
      expect(alarm.scheduled.length, 1);
      expect(alarm.scheduled.first['kind'], 'daily_fullscreen');
      expect(alarm.scheduled.first['hour'], 21);
      expect(alarm.scheduled.first['minute'], 30);
      expect(alarm.scheduled.first['fullScreen'], isTrue);
      expect(alarm.scheduled.first['snoozeMinutes'], 5);
      expect(alarm.scheduled.first['title'], '习惯打卡提醒');
      expect(alarm.scheduled.first['body'], '阅读 到时间了，点开确认打卡');
      expect(alarm.scheduled.first['payload'], 'duoyi://habit/h1?confirm=1');
    });

    test('syncHabits 闹钟通知权限异常时降级普通通知', () async {
      alarm.failDailyWithNotificationPermission = true;
      final habit = Habit(
        id: 'h1',
        name: '阅读',
        remind: true,
        remindHour: 21,
        remindMinute: 30,
      );

      await scheduler.syncHabits([habit]);

      expect(alarm.scheduled, isEmpty);
      expect(notif.scheduled.length, 1);
      expect(notif.scheduled.first['kind'], 'habit');
      expect(notif.scheduled.first['habitId'], 'h1');
      expect(notif.scheduled.first['title'], '习惯打卡提醒');
      expect(notif.scheduled.first['body'], '别忘了: 阅读');
    });

    test('syncHabits 闹钟插件异常时也降级普通通知', () async {
      alarm.failDailyWithGenericError = true;
      final habit = Habit(
        id: 'h-generic-fallback',
        name: '阅读',
        remind: true,
        remindHour: 21,
        remindMinute: 30,
      );

      await scheduler.syncHabits([habit]);

      expect(alarm.scheduled, isEmpty);
      expect(notif.scheduled.length, 1);
      expect(notif.scheduled.first['kind'], 'habit');
      expect(notif.scheduled.first['habitId'], habit.id);
    });

    test('syncHabits 闹钟半注册后异常时不降级普通通知避免双弹', () async {
      alarm
        ..failDailyWithGenericError = true
        ..rememberDailyPendingBeforeGenericError = true;
      final habit = Habit(
        id: 'h-partial-native-no-fallback',
        name: '阅读',
        remind: true,
        remindHour: 21,
        remindMinute: 30,
      );
      final expectedId = _idFor('habit_${habit.id}');

      await scheduler.syncHabits([habit]);

      expect(alarm.scheduled, isEmpty);
      expect(notif.scheduled, isEmpty);
      expect(alarm.pending, contains(expectedId));
    });

    test('syncHabits 闹钟权限异常但已入队时不降级普通通知避免双弹', () async {
      alarm
        ..failDailyWithAlarmPermission = true
        ..rememberDailyPendingBeforeAlarmPermission = true;
      final habit = Habit(
        id: 'h-permission-partial-no-fallback',
        name: '阅读',
        remind: true,
        remindHour: 21,
        remindMinute: 30,
      );
      final expectedId = _idFor('habit_${habit.id}');

      await scheduler.syncHabits([habit]);

      expect(alarm.scheduled, isEmpty);
      expect(notif.scheduled, isEmpty);
      expect(alarm.pending, contains(expectedId));
    });

    test('syncHabits 通知权限异常但闹钟已入队时不降级普通通知避免双弹', () async {
      alarm
        ..failDailyWithNotificationPermission = true
        ..rememberDailyPendingBeforeNotificationPermission = true;
      final habit = Habit(
        id: 'h-notification-permission-partial-no-fallback',
        name: '阅读',
        remind: true,
        remindHour: 21,
        remindMinute: 30,
      );
      final expectedId = _idFor('habit_${habit.id}');

      await scheduler.syncHabits([habit]);

      expect(alarm.scheduled, isEmpty);
      expect(notif.scheduled, isEmpty);
      expect(alarm.pending, contains(expectedId));
    });

    test('syncHabits 闹钟交接失败时不降级普通通知避免双弹', () async {
      alarm.failDailyWithHandoff = true;
      final habit = Habit(
        id: 'h-handoff-no-fallback',
        name: '阅读',
        remind: true,
        remindHour: 21,
        remindMinute: 30,
      );

      await scheduler.syncHabits([habit]);

      expect(alarm.scheduled, isEmpty);
      expect(notif.scheduled, isEmpty);
    });

    test('syncHabits kind=push 走普通通知而不是闹钟', () async {
      final habit = Habit(
        id: 'h-push',
        name: '喝水',
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'habit-reminder',
              type: ReminderRuleType.weeklyTime,
              kind: ReminderKind.push,
              hour: 8,
              minute: 10,
              weekdays: const [1, 3, 5],
            ),
          ],
        ),
      );

      await scheduler.syncHabits([habit]);

      expect(alarm.scheduled, isEmpty);
      expect(popup.scheduled, isEmpty);
      expect(notif.scheduled.length, 1);
      expect(notif.scheduled.single['kind'], 'habit');
      expect(notif.scheduled.single['habitId'], habit.id);
      expect(notif.scheduled.single['hour'], 8);
      expect(notif.scheduled.single['minute'], 10);
    });

    test('syncHabits kind=popup 走应用内弹窗提醒', () async {
      final habit = Habit(
        id: 'h-popup',
        name: '拉伸',
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'habit-reminder',
              type: ReminderRuleType.weeklyTime,
              kind: ReminderKind.popup,
              hour: 19,
              minute: 5,
              weekdays: const [2, 4],
            ),
          ],
        ),
      );

      await scheduler.syncHabits([habit]);

      expect(notif.scheduled, isEmpty);
      expect(alarm.scheduled, isEmpty);
      expect(popup.scheduled.length, 1);
      expect(popup.scheduled.single['kind'], 'popup_repeating');
      expect(popup.scheduled.single['id'], _idFor('habit_${habit.id}'));
      expect(popup.scheduled.single['hour'], 19);
      expect(popup.scheduled.single['minute'], 5);
      expect(
        popup.scheduled.single['payload'],
        'duoyi://habit/${habit.id}?confirm=1',
      );
    });

    test('未注入 popup sink 时，习惯 popup 会注册系统通知兜底', () async {
      final fallbackScheduler = ReminderScheduler(
        notif,
        alarm: alarm,
        registry: registry,
      );
      final habit = Habit(
        id: 'h-popup-default-fallback',
        name: '拉伸',
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'habit-reminder',
              type: ReminderRuleType.weeklyTime,
              kind: ReminderKind.popup,
              hour: 19,
              minute: 5,
              weekdays: const [2, 4],
            ),
          ],
        ),
      );

      await fallbackScheduler.syncHabits([habit]);

      expect(alarm.scheduled, isEmpty);
      expect(notif.scheduled.length, 1);
      expect(notif.scheduled.single['kind'], 'daily');
      expect(notif.scheduled.single['id'], _idFor('habit_${habit.id}'));
      expect(
        notif.scheduled.single['payload'],
        'duoyi://habit/${habit.id}?confirm=1&fallback=popup_notification',
      );
    });

    test('syncTodos 闹钟插件异常时降级一次性普通通知', () async {
      alarm.failFullScreenWithGenericError = true;
      final due = DateTime.now().add(const Duration(hours: 2));
      final todo = TodoItem(
        id: 'todo-alarm-generic-fallback',
        title: '提交材料',
        dueDate: due,
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'r1',
              type: ReminderRuleType.absolute,
              kind: ReminderKind.alarm,
              hour: due.hour,
              minute: due.minute,
              fullScreen: true,
            ),
          ],
        ),
      );

      await scheduler.syncTodos([todo]);

      expect(alarm.scheduled, isEmpty);
      expect(notif.scheduled.length, 1);
      expect(notif.scheduled.first['kind'], 'once');
      expect(
        notif.scheduled.first['payload'],
        'duoyi://todo/${todo.id}?fallback=push',
      );
    });

    test('syncTodos 一次性闹钟降级通知后二次同步不重复注册', () async {
      alarm.failFullScreenWithGenericError = true;
      final due = DateTime.now().add(const Duration(hours: 2));
      final todo = TodoItem(
        id: 'todo-alarm-fallback-idempotent',
        title: '提交材料',
        dueDate: due,
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'r1',
              type: ReminderRuleType.absolute,
              kind: ReminderKind.alarm,
              hour: due.hour,
              minute: due.minute,
              fullScreen: true,
            ),
          ],
        ),
      );

      await scheduler.syncTodos([todo]);
      notif.cancelled.clear();
      await scheduler.syncTodos([todo]);

      expect(alarm.scheduled, isEmpty);
      expect(notif.scheduled, hasLength(1));
      expect(notif.scheduled.single['id'], _idFor('todo:${todo.id}:r1'));
      expect(notif.cancelled, isEmpty);
    });

    test('syncTodos 闹钟降级通知后 pending 查询失败时记录兜底诊断', () async {
      alarm.failFullScreenWithGenericError = true;
      final due = DateTime.now().add(const Duration(hours: 2));
      final todo = TodoItem(
        id: 'todo-alarm-fallback-notif-probe-failed',
        title: '提交材料',
        dueDate: due,
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'r1',
              type: ReminderRuleType.absolute,
              kind: ReminderKind.alarm,
              hour: due.hour,
              minute: due.minute,
              fullScreen: true,
            ),
          ],
        ),
      );
      final expectedKey = 'todo:${todo.id}:r1';

      await scheduler.syncTodos([todo]);
      notif.cancelled.clear();
      notif.failPendingIds = true;
      await scheduler.syncTodos([todo]);

      expect(alarm.scheduled, isEmpty);
      expect(notif.scheduled, hasLength(1));
      expect(notif.cancelled, isEmpty);
      expect(notif.issues, hasLength(1));
      expect(notif.issues.single['title'], '普通通知兜底状态无法确认');
      expect(notif.issues.single['message'], contains('普通通知兜底队列查询失败'));
      expect(
        notif.issues.single['message'],
        contains('forced notification pending query failure'),
      );
      expect(notif.issues.single['relatedId'], expectedKey);
      expect(notif.issues.single['blocking'], isFalse);
    });

    test('syncTodos 一次性闹钟半注册后异常时不降级普通通知避免双弹', () async {
      alarm
        ..failFullScreenWithGenericError = true
        ..rememberFullScreenPendingBeforeGenericError = true;
      final due = DateTime.now().add(const Duration(hours: 2));
      final todo = TodoItem(
        id: 'todo-alarm-partial-no-fallback',
        title: '提交材料',
        dueDate: due,
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'r1',
              type: ReminderRuleType.absolute,
              kind: ReminderKind.alarm,
              hour: due.hour,
              minute: due.minute,
              fullScreen: true,
            ),
          ],
        ),
      );
      final expectedId = _idFor('todo:${todo.id}:r1');

      await scheduler.syncTodos([todo]);

      expect(alarm.scheduled, isEmpty);
      expect(notif.scheduled, isEmpty);
      expect(alarm.pending, contains(expectedId));
    });

    test('syncTodos 一次性闹钟异常且 pending 查询失败时不降级普通通知避免双弹', () async {
      alarm
        ..failFullScreenWithGenericError = true
        ..failPendingIds = true;
      final due = DateTime.now().add(const Duration(hours: 2));
      final todo = TodoItem(
        id: 'todo-alarm-pending-probe-failed-no-fallback',
        title: '提交材料',
        dueDate: due,
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'r1',
              type: ReminderRuleType.absolute,
              kind: ReminderKind.alarm,
              hour: due.hour,
              minute: due.minute,
              fullScreen: true,
            ),
          ],
        ),
      );
      final expectedId = _idFor('todo:${todo.id}:r1');

      await scheduler.syncTodos([todo]);

      expect(alarm.scheduled, isEmpty);
      expect(notif.scheduled, hasLength(1));
      expect(notif.scheduled.single['kind'], 'once');
      expect(notif.scheduled.single['id'], expectedId);
      expect(
        notif.scheduled.single['payload'],
        'duoyi://todo/${todo.id}?fallback=push',
      );
      expect(notif.issues, hasLength(1));
      expect(notif.issues.single['title'], '闹钟提醒状态无法确认');
      expect(notif.issues.single['message'], contains('系统待触发队列查询失败'));
      expect(
        notif.issues.single['message'],
        contains('forced pending query failure'),
      );
      expect(notif.issues.single['relatedId'], 'once:$expectedId');
      expect(notif.issues.single['blocking'], isFalse);
    });

    test('syncTodos 一次性闹钟权限异常但已入队时不降级普通通知避免双弹', () async {
      alarm
        ..failFullScreenWithAlarmPermission = true
        ..rememberFullScreenPendingBeforeAlarmPermission = true;
      final due = DateTime.now().add(const Duration(hours: 2));
      final todo = TodoItem(
        id: 'todo-alarm-permission-partial-no-fallback',
        title: '提交材料',
        dueDate: due,
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'r1',
              type: ReminderRuleType.absolute,
              kind: ReminderKind.alarm,
              hour: due.hour,
              minute: due.minute,
              fullScreen: true,
            ),
          ],
        ),
      );
      final expectedId = _idFor('todo:${todo.id}:r1');

      await scheduler.syncTodos([todo]);

      expect(alarm.scheduled, isEmpty);
      expect(notif.scheduled, isEmpty);
      expect(alarm.pending, contains(expectedId));
    });

    test('syncTodos 一次性通知权限异常但闹钟已入队时不降级普通通知避免双弹', () async {
      alarm
        ..failFullScreenWithNotificationPermission = true
        ..rememberFullScreenPendingBeforeNotificationPermission = true;
      final due = DateTime.now().add(const Duration(hours: 2));
      final todo = TodoItem(
        id: 'todo-alarm-notification-permission-partial-no-fallback',
        title: '提交材料',
        dueDate: due,
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'r1',
              type: ReminderRuleType.absolute,
              kind: ReminderKind.alarm,
              hour: due.hour,
              minute: due.minute,
              fullScreen: true,
            ),
          ],
        ),
      );
      final expectedId = _idFor('todo:${todo.id}:r1');

      await scheduler.syncTodos([todo]);

      expect(alarm.scheduled, isEmpty);
      expect(notif.scheduled, isEmpty);
      expect(alarm.pending, contains(expectedId));
    });

    test('未注入 popup sink 时，待办 popup 会注册系统通知兜底', () async {
      final fallbackScheduler = ReminderScheduler(
        notif,
        alarm: alarm,
        registry: registry,
      );
      final due = DateTime.now().add(const Duration(hours: 2));
      final todo = TodoItem(
        id: 'todo-popup-default-fallback',
        title: '弹窗待办',
        dueDate: due,
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'popup-once',
              type: ReminderRuleType.absolute,
              kind: ReminderKind.popup,
              hour: due.hour,
              minute: due.minute,
            ),
          ],
        ),
      );

      await fallbackScheduler.syncTodos([todo]);

      expect(alarm.scheduled, isEmpty);
      expect(notif.scheduled.length, 1);
      expect(notif.scheduled.single['kind'], 'once');
      expect(
        notif.scheduled.single['id'],
        _idFor('todo:${todo.id}:popup-once'),
      );
      expect(
        notif.scheduled.single['payload'],
        'duoyi://todo/${todo.id}?fallback=popup_notification',
      );
    });

    test('显式 Noop popup sink 不会把 popup 待办缓存为已调度', () async {
      final noopScheduler = ReminderScheduler(
        notif,
        alarm: alarm,
        popup: const NoopReminderPopupSink(),
        registry: registry,
      );
      final due = DateTime.now().add(const Duration(hours: 2));
      final todo = TodoItem(
        id: 'todo-popup-noop-retry',
        title: '弹窗待办',
        dueDate: due,
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'popup-once',
              type: ReminderRuleType.absolute,
              kind: ReminderKind.popup,
              hour: due.hour,
              minute: due.minute,
            ),
          ],
        ),
      );

      await noopScheduler.syncTodos([todo]);
      await noopScheduler.syncTodos([todo]);

      expect(notif.scheduled, isEmpty);
      expect(alarm.scheduled, isEmpty);
      expect(noopScheduler.debugScheduledTodoRuleCount(todo.id), 0);
    });

    test('syncTodos 闹钟和一次性 push 都失败时不记为已调度，权限恢复后重试', () async {
      alarm.failFullScreenWithGenericError = true;
      notif.denyScheduleOnce = true;
      final due = DateTime.now().add(const Duration(hours: 2));
      final todo = TodoItem(
        id: 'todo-alarm-fallback-retry',
        title: '提交材料',
        dueDate: due,
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'r1',
              type: ReminderRuleType.absolute,
              kind: ReminderKind.alarm,
              hour: due.hour,
              minute: due.minute,
              fullScreen: true,
            ),
          ],
        ),
      );

      await scheduler.syncTodos([todo]);

      expect(alarm.scheduled, isEmpty);
      expect(notif.scheduled, isEmpty);

      notif.denyScheduleOnce = false;
      await scheduler.syncTodos([todo]);

      expect(notif.scheduled.length, 1);
      expect(notif.scheduled.single['kind'], 'once');
      expect(
        notif.scheduled.single['payload'],
        'duoyi://todo/${todo.id}?fallback=push',
      );
    });

    test('syncTodos 闹钟通知权限失败时不记为已调度，权限恢复后重试', () async {
      alarm.failFullScreenWithNotificationPermission = true;
      final due = DateTime.now().add(const Duration(hours: 2));
      final todo = TodoItem(
        id: 'todo-alarm-notification-permission-retry',
        title: '提交材料',
        dueDate: due,
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'r1',
              type: ReminderRuleType.absolute,
              kind: ReminderKind.alarm,
              hour: due.hour,
              minute: due.minute,
              fullScreen: true,
            ),
          ],
        ),
      );

      await scheduler.syncTodos([todo]);

      expect(alarm.scheduled, isEmpty);
      expect(notif.scheduled, isEmpty);

      alarm.failFullScreenWithNotificationPermission = false;
      await scheduler.syncTodos([todo]);

      expect(alarm.scheduled.length, 1);
      expect(alarm.scheduled.single['kind'], 'fullscreen');
      expect(
        alarm.scheduled.single['payload'],
        'duoyi://todo/${todo.id}?confirm=1',
      );
    });

    test('syncTodos 精准闹钟权限失败且 push 插件异常时不抛出', () async {
      alarm.failFullScreenWithAlarmPermission = true;
      notif.failScheduleOnceGeneric = true;
      final due = DateTime.now().add(const Duration(hours: 2));
      final todo = TodoItem(
        id: 'todo-alarm-permission-fallback-generic',
        title: '提交材料',
        dueDate: due,
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'r1',
              type: ReminderRuleType.absolute,
              kind: ReminderKind.alarm,
              hour: due.hour,
              minute: due.minute,
              fullScreen: true,
            ),
          ],
        ),
      );

      await scheduler.syncTodos([todo]);

      expect(alarm.scheduled, isEmpty);
      expect(notif.scheduled, isEmpty);
    });

    test('syncTodos 重复闹钟插件异常时降级重复普通通知', () async {
      alarm.failDailyWithGenericError = true;
      final todo = TodoItem(
        id: 'todo-repeating-alarm-generic-fallback',
        title: '每日复盘',
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'daily',
              type: ReminderRuleType.dailyTime,
              kind: ReminderKind.alarm,
              hour: 20,
              minute: 45,
            ),
          ],
        ),
      );

      await scheduler.syncTodos([todo]);

      expect(alarm.scheduled, isEmpty);
      expect(notif.scheduled.length, 1);
      expect(notif.scheduled.first['kind'], 'daily');
      expect(notif.scheduled.first['hour'], 20);
      expect(notif.scheduled.first['minute'], 45);
      expect(
        notif.scheduled.first['payload'],
        'duoyi://todo/${todo.id}?fallback=push',
      );
    });

    test('syncTodos 重复闹钟降级通知后二次同步不重复注册', () async {
      alarm.failDailyWithGenericError = true;
      final todo = TodoItem(
        id: 'todo-repeating-alarm-fallback-idempotent',
        title: '每日复盘',
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'daily',
              type: ReminderRuleType.dailyTime,
              kind: ReminderKind.alarm,
              hour: 20,
              minute: 45,
              weekdays: const [1, 3, 5],
            ),
          ],
        ),
      );

      await scheduler.syncTodos([todo]);
      notif.cancelled.clear();
      await scheduler.syncTodos([todo]);

      expect(alarm.scheduled, isEmpty);
      expect(notif.scheduled, hasLength(1));
      expect(notif.scheduled.single['id'], _idFor('todo:${todo.id}:daily'));
      expect(notif.cancelled, isEmpty);
    });

    test('syncTodos 重复闹钟半注册后异常时不降级普通通知避免双弹', () async {
      alarm
        ..failDailyWithGenericError = true
        ..rememberDailyPendingBeforeGenericError = true;
      final todo = TodoItem(
        id: 'todo-repeating-alarm-partial-no-fallback',
        title: '每日复盘',
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'weekly',
              type: ReminderRuleType.weeklyTime,
              kind: ReminderKind.alarm,
              hour: 20,
              minute: 45,
              weekdays: const [1, 3],
            ),
          ],
        ),
      );
      final expectedId = _idFor('todo:${todo.id}:weekly');

      await scheduler.syncTodos([todo]);

      expect(alarm.scheduled, isEmpty);
      expect(notif.scheduled, isEmpty);
      expect(
        alarm.pending,
        containsAll([_subId(expectedId, 1), _subId(expectedId, 3)]),
      );
    });

    test('syncTodos 重复闹钟异常且 pending 查询失败时不降级普通通知避免双弹', () async {
      alarm
        ..failDailyWithGenericError = true
        ..failPendingIds = true;
      final todo = TodoItem(
        id: 'todo-repeating-alarm-pending-probe-failed-no-fallback',
        title: '每日复盘',
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'weekly',
              type: ReminderRuleType.weeklyTime,
              kind: ReminderKind.alarm,
              hour: 20,
              minute: 45,
              weekdays: const [1, 3],
            ),
          ],
        ),
      );
      final expectedKey = 'todo:${todo.id}:weekly';
      final expectedId = _idFor(expectedKey);

      await scheduler.syncTodos([todo]);

      expect(alarm.scheduled, isEmpty);
      expect(notif.scheduled, hasLength(1));
      expect(notif.scheduled.single['kind'], 'daily');
      expect(notif.scheduled.single['id'], expectedId);
      expect(
        notif.scheduled.single['payload'],
        'duoyi://todo/${todo.id}?fallback=push',
      );
      expect(notif.issues, hasLength(1));
      expect(notif.issues.single['title'], '闹钟提醒状态无法确认');
      expect(notif.issues.single['message'], contains('系统待触发队列查询失败'));
      expect(
        notif.issues.single['message'],
        contains('forced pending query failure'),
      );
      expect(notif.issues.single['relatedId'], expectedKey);
      expect(notif.issues.single['blocking'], isFalse);
    });

    test('syncTodos 重复闹钟权限异常但已入队时不降级普通通知避免双弹', () async {
      alarm
        ..failDailyWithAlarmPermission = true
        ..rememberDailyPendingBeforeAlarmPermission = true;
      final todo = TodoItem(
        id: 'todo-repeating-permission-partial-no-fallback',
        title: '每日复盘',
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'weekly',
              type: ReminderRuleType.weeklyTime,
              kind: ReminderKind.alarm,
              hour: 20,
              minute: 45,
              weekdays: const [1, 3],
            ),
          ],
        ),
      );
      final expectedId = _idFor('todo:${todo.id}:weekly');

      await scheduler.syncTodos([todo]);

      expect(alarm.scheduled, isEmpty);
      expect(notif.scheduled, isEmpty);
      expect(
        alarm.pending,
        containsAll([_subId(expectedId, 1), _subId(expectedId, 3)]),
      );
    });

    test('syncTodos 重复通知权限异常但闹钟已入队时不降级普通通知避免双弹', () async {
      alarm
        ..failDailyWithNotificationPermission = true
        ..rememberDailyPendingBeforeNotificationPermission = true;
      final todo = TodoItem(
        id: 'todo-repeating-notification-permission-partial-no-fallback',
        title: '每日复盘',
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'weekly',
              type: ReminderRuleType.weeklyTime,
              kind: ReminderKind.alarm,
              hour: 20,
              minute: 45,
              weekdays: const [1, 3],
            ),
          ],
        ),
      );
      final expectedId = _idFor('todo:${todo.id}:weekly');

      await scheduler.syncTodos([todo]);

      expect(alarm.scheduled, isEmpty);
      expect(notif.scheduled, isEmpty);
      expect(
        alarm.pending,
        containsAll([_subId(expectedId, 1), _subId(expectedId, 3)]),
      );
    });

    test('syncTodos 重复闹钟和重复 push 都失败时不记为已调度，权限恢复后重试', () async {
      alarm.failDailyWithGenericError = true;
      notif.denyScheduleDaily = true;
      final todo = TodoItem(
        id: 'todo-repeating-alarm-fallback-retry',
        title: '每日复盘',
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'daily',
              type: ReminderRuleType.dailyTime,
              kind: ReminderKind.alarm,
              hour: 20,
              minute: 45,
            ),
          ],
        ),
      );

      await scheduler.syncTodos([todo]);

      expect(alarm.scheduled, isEmpty);
      expect(notif.scheduled, isEmpty);

      notif.denyScheduleDaily = false;
      await scheduler.syncTodos([todo]);

      expect(notif.scheduled.length, 1);
      expect(notif.scheduled.single['kind'], 'daily');
      expect(
        notif.scheduled.single['payload'],
        'duoyi://todo/${todo.id}?fallback=push',
      );
    });

    test('syncTodos 重复闹钟权限失败且 push 插件异常时不抛出', () async {
      alarm.failDailyWithAlarmPermission = true;
      notif.failScheduleDailyGeneric = true;
      final todo = TodoItem(
        id: 'todo-repeating-permission-fallback-generic',
        title: '每日复盘',
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'daily',
              type: ReminderRuleType.dailyTime,
              kind: ReminderKind.alarm,
              hour: 20,
              minute: 45,
            ),
          ],
        ),
      );

      await scheduler.syncTodos([todo]);

      expect(alarm.scheduled, isEmpty);
      expect(notif.scheduled, isEmpty);
    });

    test('syncHabits 闹钟和 push 都失败时不记为已调度，权限恢复后会重试', () async {
      alarm.failDailyWithNotificationPermission = true;
      notif.denyHabitReminder = true;
      final habit = Habit(
        id: 'h-retry',
        name: '阅读',
        remind: true,
        remindHour: 21,
        remindMinute: 30,
      );

      await scheduler.syncHabits([habit]);

      expect(alarm.scheduled, isEmpty);
      expect(notif.scheduled, isEmpty);

      notif.denyHabitReminder = false;
      await scheduler.syncHabits([habit]);

      expect(notif.scheduled.length, 1);
      expect(notif.scheduled.single['kind'], 'habit');
      expect(notif.scheduled.single['habitId'], habit.id);
    });

    test('syncHabits 闹钟降级通知后二次同步不重复注册', () async {
      alarm.failDailyWithGenericError = true;
      final habit = Habit(
        id: 'h-alarm-fallback-idempotent',
        name: '阅读',
        remind: true,
        remindHour: 21,
        remindMinute: 30,
      );

      await scheduler.syncHabits([habit]);
      notif.cancelledHabits.clear();
      await scheduler.syncHabits([habit]);

      expect(alarm.scheduled, isEmpty);
      expect(notif.scheduled, hasLength(1));
      expect(notif.scheduled.single['kind'], 'habit');
      expect(notif.scheduled.single['habitId'], habit.id);
      expect(notif.cancelledHabits, isEmpty);
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
      expect(notif.scheduled, isEmpty);
      expect(alarm.scheduled.length, 1);
      final h1Off = Habit(id: 'h1', name: '阅读', remind: false);
      await scheduler.syncHabits([h1Off]);
      expect(notif.cancelledHabits, contains('h1'));
      expect(alarm.cancelled, contains(_idFor('habit_h1')));
    });

    test('syncHabits 冷启动关闭提醒会清理已持久化的旧提醒', () async {
      final habit = Habit(
        id: 'habit-cold-start-off',
        name: '阅读',
        remind: true,
        remindHour: 9,
        remindMinute: 0,
      );
      final id = _idFor('habit_${habit.id}');
      await scheduler.syncHabits([habit]);
      expect(alarm.pending, contains(id));

      final coldScheduler = ReminderScheduler(
        notif,
        alarm: alarm,
        popup: popup,
        email: email,
        registry: registry,
      );
      final off = Habit(id: habit.id, name: habit.name, remind: false);
      await coldScheduler.syncHabits([off]);

      expect(notif.cancelledHabits, contains(habit.id));
      expect(alarm.cancelled, contains(id));
      expect(popup.cancelled, contains(id));
      expect(email.cancelled, contains(id));
      expect(alarm.pending, isNot(contains(id)));
    });

    test('syncHabits 同一提醒重复同步不会取消重放', () async {
      final habit = Habit(
        id: 'h-idempotent',
        name: '阅读',
        remind: true,
        remindHour: 21,
        remindMinute: 30,
        activeWeekdays: const [0, 2, 4],
      );

      await scheduler.syncHabits([habit]);
      notif.cancelledHabits.clear();
      alarm.cancelled.clear();
      await scheduler.syncHabits([habit]);

      expect(alarm.scheduled.length, 1);
      expect(notif.cancelledHabits, isEmpty);
      expect(alarm.cancelled, isEmpty);
    });

    test('syncHabits 每周原生闹钟 base id pending 时不会重复重注册', () async {
      final habit = Habit(
        id: 'h-native-weekly-base-pending',
        name: '阅读',
        remind: true,
        remindHour: 21,
        remindMinute: 30,
        activeWeekdays: const [0, 2, 4],
      );
      final expectedId = _idFor('habit_${habit.id}');

      await scheduler.syncHabits([habit]);
      expect(alarm.scheduled.map((entry) => entry['id']), [expectedId]);

      alarm.pending
        ..clear()
        ..add(expectedId);
      final scheduledBefore = alarm.scheduled.length;
      final cancelledBefore = alarm.cancelled.length;

      await scheduler.syncHabits([habit]);

      expect(alarm.scheduled, hasLength(scheduledBefore));
      expect(alarm.cancelled, hasLength(cancelledBefore));
      expect(alarm.pending, contains(expectedId));
    });

    test('syncHabits 每周闹钟规则未变时会清理旧版普通通知子 id，避免双弹', () async {
      final habit = Habit(
        id: 'h-native-weekly-stale-legacy-push',
        name: '阅读',
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'habit-reminder',
              type: ReminderRuleType.weeklyTime,
              kind: ReminderKind.alarm,
              hour: 21,
              minute: 30,
              weekdays: const [1, 3, 5],
            ),
          ],
        ),
      );
      final expectedId = _idFor('habit_${habit.id}');
      final mondayId = _subId(expectedId, 1);
      final wednesdayId = _subId(expectedId, 3);
      final legacyMondayId = _legacySubId(expectedId, 1);

      await scheduler.syncHabits([habit]);
      expect(alarm.scheduled.map((entry) => entry['id']), [expectedId]);
      expect(alarm.pending, containsAll([mondayId, wednesdayId]));

      notif.pending.add(legacyMondayId);
      alarm.scheduled.clear();
      await scheduler.syncHabits([habit]);

      expect(alarm.scheduled, isEmpty);
      expect(notif.cancelled, contains(legacyMondayId));
      expect(notif.pending, isNot(contains(legacyMondayId)));
      expect(alarm.pending, containsAll([mondayId, wednesdayId]));
    });

    test('syncHabits 规则未变但 push pending 丢失时会重新注册', () async {
      final habit = Habit(
        id: 'h-push-pending-lost',
        name: '喝水',
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'habit-reminder',
              type: ReminderRuleType.weeklyTime,
              kind: ReminderKind.push,
              hour: 8,
              minute: 10,
              weekdays: const [1, 3, 5],
            ),
          ],
        ),
      );
      final baseId = _idFor('habit_${habit.id}');
      final mondayId = _subId(baseId, 1);

      await scheduler.syncHabits([habit]);
      expect(notif.scheduled.map((entry) => entry['habitId']), [habit.id]);
      expect(notif.pending, contains(mondayId));

      notif.pending.remove(mondayId);
      await scheduler.syncHabits([habit]);

      expect(notif.cancelledHabits, contains(habit.id));
      expect(
        notif.scheduled.where((entry) => entry['habitId'] == habit.id),
        hasLength(2),
      );
      expect(notif.pending, contains(mondayId));
    });

    test('syncHabits 修改时间后取消旧调度并重新下发', () async {
      final habit = Habit(
        id: 'h-reschedule',
        name: '阅读',
        remind: true,
        remindHour: 21,
        remindMinute: 30,
      );
      final edited = habit.copyWith(remindHour: 22, remindMinute: 0);

      await scheduler.syncHabits([habit]);
      await scheduler.syncHabits([edited]);

      expect(notif.cancelledHabits, contains(habit.id));
      expect(alarm.cancelled, contains(_idFor('habit_${habit.id}')));
      expect(alarm.scheduled.length, 2);
      expect(alarm.scheduled.last['hour'], 22);
      expect(alarm.scheduled.last['minute'], 0);
    });

    test('syncAnniversaries 默认走 push 通道', () async {
      final a = Anniversary(
        title: '生日',
        originDate: DateTime.now().add(const Duration(days: 30)),
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
        originDate: DateTime.now().add(const Duration(days: 30)),
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

    test('syncAnniversaries kind=popup 走弹出框提醒', () async {
      final a = Anniversary(
        id: 'ann-popup',
        title: '弹窗纪念',
        originDate: DateTime.now().add(const Duration(days: 30)),
        type: AnniversaryType.memorial,
        remind: true,
        remindDaysBefore: 1,
        remindHour: 9,
        reminderKind: ReminderKind.popup,
      );

      await scheduler.syncAnniversaries([a]);

      expect(notif.scheduled, isEmpty);
      expect(alarm.scheduled, isEmpty);
      expect(popup.scheduled.length, 1);
      expect(popup.scheduled.single['kind'], 'popup_once');
      expect(popup.scheduled.single['id'], _anniversaryPopupId(a.id));
      expect(popup.scheduled.single['payload'], 'duoyi://anniversary/${a.id}');
    });

    test('syncAnniversaries popup 调度失败时不缓存成功状态，恢复后会重试', () async {
      final a = Anniversary(
        id: 'ann-popup-retry',
        title: '弹窗重试纪念',
        originDate: DateTime.now().add(const Duration(days: 30)),
        type: AnniversaryType.memorial,
        remind: true,
        remindDaysBefore: 1,
        remindHour: 9,
        reminderKind: ReminderKind.popup,
      );

      popup.failOnce = true;
      await scheduler.syncAnniversaries([a]);

      expect(popup.scheduled, isEmpty);

      popup.failOnce = false;
      await scheduler.syncAnniversaries([a]);

      expect(popup.scheduled.length, 1);
      expect(popup.scheduled.single['id'], _anniversaryPopupId(a.id));
    });

    test('syncAnniversaries kind=off 会清理旧提醒且不重新注册', () async {
      final origin = DateTime.now().add(const Duration(days: 30));
      final push = Anniversary(
        id: 'ann-off',
        title: '关闭纪念',
        originDate: origin,
        remind: true,
        remindDaysBefore: 1,
        remindHour: 9,
        reminderKind: ReminderKind.push,
      );
      final off = Anniversary(
        id: push.id,
        title: push.title,
        originDate: origin,
        remind: true,
        remindDaysBefore: 1,
        remindHour: 9,
        reminderKind: ReminderKind.off,
      );

      await scheduler.syncAnniversaries([push]);
      await scheduler.syncAnniversaries([off]);

      expect(notif.cancelledAnniversaries, contains(push.id));
      expect(alarm.cancelled, contains(_anniversaryAlarmId(push.id)));
      expect(popup.cancelled, contains(_anniversaryPopupId(push.id)));
      expect(notif.scheduled.length, 1);
      expect(alarm.scheduled, isEmpty);
      expect(popup.scheduled, isEmpty);
    });

    test('syncAnniversaries alarm 和 push fallback 都失败时不抛异常且可重试', () async {
      alarm.failFullScreenWithAlarmPermission = true;
      notif.denyAnniversary = true;
      final a = Anniversary(
        id: 'ann-retry',
        title: '重要纪念',
        originDate: DateTime.now().add(const Duration(days: 30)),
        type: AnniversaryType.memorial,
        remind: true,
        remindDaysBefore: 1,
        remindHour: 9,
        reminderKind: ReminderKind.alarm,
      );

      await scheduler.syncAnniversaries([a]);

      expect(alarm.scheduled, isEmpty);
      expect(notif.scheduled, isEmpty);

      notif.denyAnniversary = false;
      await scheduler.syncAnniversaries([a]);

      expect(notif.scheduled.length, 1);
      expect(notif.scheduled.single['kind'], 'anniversary_push');
      expect(notif.scheduled.single['id'], a.id);
    });

    test('syncAnniversaries 闹钟降级通知后二次同步不重复注册', () async {
      alarm.failFullScreenWithGenericError = true;
      final a = Anniversary(
        id: 'ann-alarm-fallback-idempotent',
        title: '重要纪念',
        originDate: DateTime.now().add(const Duration(days: 30)),
        type: AnniversaryType.memorial,
        remind: true,
        remindDaysBefore: 1,
        remindHour: 9,
        reminderKind: ReminderKind.alarm,
      );

      await scheduler.syncAnniversaries([a]);
      notif.cancelledAnniversaries.clear();
      await scheduler.syncAnniversaries([a]);

      expect(alarm.scheduled, isEmpty);
      expect(notif.scheduled, hasLength(1));
      expect(notif.scheduled.single['kind'], 'anniversary_push');
      expect(notif.scheduled.single['id'], a.id);
      expect(notif.cancelledAnniversaries, isEmpty);
    });

    test('syncAnniversaries 闹钟交接失败时不降级普通通知避免双弹', () async {
      alarm.failFullScreenWithHandoff = true;
      final a = Anniversary(
        id: 'ann-handoff-no-fallback',
        title: '重要纪念',
        originDate: DateTime.now().add(const Duration(days: 30)),
        type: AnniversaryType.memorial,
        remind: true,
        remindDaysBefore: 1,
        remindHour: 9,
        reminderKind: ReminderKind.alarm,
      );

      await scheduler.syncAnniversaries([a]);

      expect(alarm.scheduled, isEmpty);
      expect(notif.scheduled, isEmpty);
    });

    test('syncAnniversaries 闹钟半注册后异常时不降级普通通知避免双弹', () async {
      alarm
        ..failFullScreenWithGenericError = true
        ..rememberFullScreenPendingBeforeGenericError = true;
      final a = Anniversary(
        id: 'ann-partial-native-no-fallback',
        title: '重要纪念',
        originDate: DateTime.now().add(const Duration(days: 30)),
        type: AnniversaryType.memorial,
        remind: true,
        remindDaysBefore: 1,
        remindHour: 9,
        reminderKind: ReminderKind.alarm,
      );
      final expectedId = _anniversaryAlarmId(a.id);

      await scheduler.syncAnniversaries([a]);

      expect(alarm.scheduled, isEmpty);
      expect(notif.scheduled, isEmpty);
      expect(alarm.pending, contains(expectedId));
    });

    test('syncAnniversaries 闹钟权限异常但已入队时不降级普通通知避免双弹', () async {
      alarm
        ..failFullScreenWithAlarmPermission = true
        ..rememberFullScreenPendingBeforeAlarmPermission = true;
      final a = Anniversary(
        id: 'ann-permission-partial-no-fallback',
        title: '重要纪念',
        originDate: DateTime.now().add(const Duration(days: 30)),
        type: AnniversaryType.memorial,
        remind: true,
        remindDaysBefore: 1,
        remindHour: 9,
        reminderKind: ReminderKind.alarm,
      );
      final expectedId = _anniversaryAlarmId(a.id);

      await scheduler.syncAnniversaries([a]);

      expect(alarm.scheduled, isEmpty);
      expect(notif.scheduled, isEmpty);
      expect(alarm.pending, contains(expectedId));
    });

    test('syncAnniversaries 通知权限异常但闹钟已入队时不降级普通通知避免双弹', () async {
      alarm
        ..failFullScreenWithNotificationPermission = true
        ..rememberFullScreenPendingBeforeNotificationPermission = true;
      final a = Anniversary(
        id: 'ann-notification-permission-partial-no-fallback',
        title: '重要纪念',
        originDate: DateTime.now().add(const Duration(days: 30)),
        type: AnniversaryType.memorial,
        remind: true,
        remindDaysBefore: 1,
        remindHour: 9,
        reminderKind: ReminderKind.alarm,
      );
      final expectedId = _anniversaryAlarmId(a.id);

      await scheduler.syncAnniversaries([a]);

      expect(alarm.scheduled, isEmpty);
      expect(notif.scheduled, isEmpty);
      expect(alarm.pending, contains(expectedId));
    });

    test('syncAnniversaries 同一提醒重复同步不会重复注册', () async {
      final a = Anniversary(
        id: 'ann-idempotent',
        title: '纪念日',
        originDate: DateTime.now().add(const Duration(days: 30)),
        remind: true,
        remindDaysBefore: 1,
        remindHour: 9,
        reminderKind: ReminderKind.push,
      );

      await scheduler.syncAnniversaries([a]);
      notif.cancelledAnniversaries.clear();
      alarm.cancelled.clear();
      await scheduler.syncAnniversaries([a]);

      expect(notif.scheduled.length, 1);
      expect(notif.cancelledAnniversaries, isEmpty);
      expect(alarm.cancelled, isEmpty);
    });

    test('syncAnniversaries 规则未变但 push pending 丢失时会重新注册', () async {
      final a = Anniversary(
        id: 'ann-pending-lost',
        title: '纪念日',
        originDate: DateTime.now().add(const Duration(days: 30)),
        remind: true,
        remindDaysBefore: 1,
        remindHour: 9,
        reminderKind: ReminderKind.push,
      );
      final expectedId = _idFor('anni_${a.id}');

      await scheduler.syncAnniversaries([a]);
      expect(notif.scheduled.map((entry) => entry['id']), [a.id]);
      expect(notif.pending, contains(expectedId));

      notif.pending.remove(expectedId);
      await scheduler.syncAnniversaries([a]);

      expect(notif.cancelledAnniversaries, contains(a.id));
      expect(
        notif.scheduled.where((entry) => entry['id'] == a.id),
        hasLength(2),
      );
      expect(notif.pending, contains(expectedId));
    });

    test('syncAnniversaries push 切到 alarm 时双通道清理旧提醒', () async {
      final origin = DateTime.now().add(const Duration(days: 30));
      final push = Anniversary(
        id: 'ann-switch',
        title: '切换提醒',
        originDate: origin,
        remind: true,
        remindDaysBefore: 1,
        remindHour: 9,
        reminderKind: ReminderKind.push,
      );
      final alarmAnniversary = Anniversary(
        id: push.id,
        title: push.title,
        originDate: origin,
        remind: true,
        remindDaysBefore: 1,
        remindHour: 9,
        reminderKind: ReminderKind.alarm,
      );

      await scheduler.syncAnniversaries([push]);
      await scheduler.syncAnniversaries([alarmAnniversary]);

      expect(notif.cancelledAnniversaries, contains(push.id));
      expect(alarm.cancelled, contains(_anniversaryAlarmId(push.id)));
      expect(alarm.scheduled.length, 1);
      expect(
        alarm.scheduled.single['payload'],
        'duoyi://anniversary/${push.id}',
      );
    });

    test('syncAnniversaries alarm 切到 push 时清理旧闹钟提醒', () async {
      final origin = DateTime.now().add(const Duration(days: 30));
      final alarmAnniversary = Anniversary(
        id: 'ann-switch-back',
        title: '切回提醒',
        originDate: origin,
        remind: true,
        remindDaysBefore: 1,
        remindHour: 9,
        reminderKind: ReminderKind.alarm,
      );
      final push = Anniversary(
        id: alarmAnniversary.id,
        title: alarmAnniversary.title,
        originDate: origin,
        remind: true,
        remindDaysBefore: 1,
        remindHour: 9,
        reminderKind: ReminderKind.push,
      );

      await scheduler.syncAnniversaries([alarmAnniversary]);
      await scheduler.syncAnniversaries([push]);

      expect(notif.cancelledAnniversaries, contains(push.id));
      expect(alarm.cancelled, contains(_anniversaryAlarmId(push.id)));
      expect(
        notif.scheduled.where((call) => call['id'] == push.id),
        hasLength(1),
      );
    });

    test('resyncAll 会清理并重放纪念日闹钟提醒', () async {
      final a = Anniversary(
        id: 'ann-resync',
        title: '重放提醒',
        originDate: DateTime.now().add(const Duration(days: 30)),
        remind: true,
        remindDaysBefore: 1,
        remindHour: 9,
        reminderKind: ReminderKind.alarm,
      );

      await scheduler.syncAnniversaries([a]);
      await scheduler.resyncAll(
        todos: const [],
        habits: const [],
        annis: [a],
        goals: const [],
      );

      expect(notif.cancelledAnniversaries, contains(a.id));
      expect(alarm.cancelled, contains(_anniversaryAlarmId(a.id)));
      expect(alarm.scheduled.length, 2);
    });

    test('resyncAll 取消某个通道失败时继续清理且不重放失败对象', () async {
      final a = Anniversary(
        id: 'ann-resync-cancel-failure',
        title: '重放失败清理',
        originDate: DateTime.now().add(const Duration(days: 30)),
        remind: true,
        remindDaysBefore: 1,
        remindHour: 9,
        reminderKind: ReminderKind.alarm,
      );

      await scheduler.syncAnniversaries([a]);
      notif.failCancelAnniversary = true;

      await scheduler.resyncAll(
        todos: const [],
        habits: const [],
        annis: [a],
        goals: const [],
      );

      expect(alarm.cancelled, contains(_anniversaryAlarmId(a.id)));
      expect(popup.cancelled, contains(_anniversaryPopupId(a.id)));
      expect(alarm.scheduled.length, 1);
    });

    test('syncCountdowns 按提醒方式路由到通知、弹出框和闹钟', () async {
      final target = DateTime.now().add(const Duration(days: 7));
      final push = CountdownItem(
        id: 'countdown-push',
        title: '通知倒数日',
        targetDate: target,
        remind: true,
        remindDaysBefore: 1,
        reminderKind: ReminderKind.push,
      );
      final popupItem = CountdownItem(
        id: 'countdown-popup',
        title: '弹窗倒数日',
        targetDate: target,
        remind: true,
        remindDaysBefore: 1,
        reminderKind: ReminderKind.popup,
      );
      final alarmItem = CountdownItem(
        id: 'countdown-alarm',
        title: '闹钟倒数日',
        targetDate: target,
        remind: true,
        remindDaysBefore: 1,
        reminderKind: ReminderKind.alarm,
      );

      await scheduler.syncCountdowns([push, popupItem, alarmItem]);

      expect(
        notif.scheduled.map((item) => item['id']),
        contains(_idFor('countdown:${push.id}:due')),
      );
      expect(
        popup.scheduled.map((item) => item['id']),
        contains(_idFor('countdown:${popupItem.id}:due')),
      );
      expect(
        alarm.scheduled.map((item) => item['id']),
        contains(_idFor('countdown:${alarmItem.id}:due')),
      );
    });

    test(
      'syncCountdowns skips reminder kind off even when remind is true',
      () async {
        final item = CountdownItem(
          id: 'countdown-off',
          title: '关闭提醒',
          targetDate: DateTime.now().add(const Duration(days: 7)),
          remind: true,
          remindDaysBefore: 1,
          reminderKind: ReminderKind.off,
        );

        await scheduler.syncCountdowns([item]);

        expect(notif.scheduled, isEmpty);
        expect(popup.scheduled, isEmpty);
        expect(alarm.scheduled, isEmpty);
      },
    );

    test('syncCountdowns popup 调度失败时不缓存成功状态，恢复后会重试', () async {
      final target = DateTime.now().add(const Duration(days: 7));
      final item = CountdownItem(
        id: 'countdown-popup-retry',
        title: '弹窗倒数重试',
        targetDate: target,
        remind: true,
        remindDaysBefore: 1,
        reminderKind: ReminderKind.popup,
      );
      final expectedId = _idFor('countdown:${item.id}:due');

      popup.failOnce = true;
      await scheduler.syncCountdowns([item]);

      expect(popup.scheduled, isEmpty);

      popup.failOnce = false;
      await scheduler.syncCountdowns([item]);

      expect(popup.scheduled.map((entry) => entry['id']), contains(expectedId));
    });

    test('syncCountdowns 弹出框规则未变时会清理残留通知和闹钟，避免双弹', () async {
      final target = DateTime.now().add(const Duration(days: 7));
      final item = CountdownItem(
        id: 'countdown-popup-stale-peers',
        title: '弹窗倒数残留',
        targetDate: target,
        remind: true,
        remindDaysBefore: 1,
        reminderKind: ReminderKind.popup,
      );
      final expectedId = _idFor('countdown:${item.id}:due');

      await scheduler.syncCountdowns([item]);
      expect(popup.scheduled.map((entry) => entry['id']), contains(expectedId));

      notif.pending.add(expectedId);
      alarm.pending.add(expectedId);
      popup.scheduled.clear();
      await scheduler.syncCountdowns([item]);

      expect(popup.scheduled, isEmpty);
      expect(notif.cancelled, contains(expectedId));
      expect(alarm.cancelled, contains(expectedId));
      expect(notif.pending, isNot(contains(expectedId)));
      expect(alarm.pending, isNot(contains(expectedId)));
    });

    test('syncCountdowns 通知权限异常但闹钟已入队时不降级普通通知避免双弹', () async {
      alarm
        ..failFullScreenWithNotificationPermission = true
        ..rememberFullScreenPendingBeforeNotificationPermission = true;
      final target = DateTime.now().add(const Duration(days: 7));
      final item = CountdownItem(
        id: 'countdown-notification-permission-partial-no-fallback',
        title: '倒数提醒',
        targetDate: target,
        remind: true,
        remindDaysBefore: 1,
        reminderKind: ReminderKind.alarm,
      );
      final expectedId = _idFor('countdown:${item.id}:due');

      await scheduler.syncCountdowns([item]);

      expect(alarm.scheduled, isEmpty);
      expect(notif.scheduled, isEmpty);
      expect(alarm.pending, contains(expectedId));
    });

    test('未注入 popup sink 时，倒数 popup 会注册系统通知兜底', () async {
      final fallbackScheduler = ReminderScheduler(
        notif,
        alarm: alarm,
        registry: registry,
      );
      final target = DateTime.now().add(const Duration(days: 7));
      final item = CountdownItem(
        id: 'countdown-popup-default-fallback',
        title: '弹窗倒数兜底',
        targetDate: target,
        remind: true,
        remindDaysBefore: 1,
        reminderKind: ReminderKind.popup,
      );
      final expectedId = _idFor('countdown:${item.id}:due');

      await fallbackScheduler.syncCountdowns([item]);

      expect(alarm.scheduled, isEmpty);
      expect(notif.scheduled.map((entry) => entry['id']), contains(expectedId));
      expect(
        notif.scheduled.singleWhere(
          (entry) => entry['id'] == expectedId,
        )['payload'],
        'duoyi://countdown/${item.id}?fallback=popup_notification',
      );
    });

    test('syncCountdowns push 插件异常时不缓存成功状态，恢复后会重试', () async {
      final target = DateTime.now().add(const Duration(days: 7));
      final item = CountdownItem(
        id: 'countdown-push-retry',
        title: '通知倒数重试',
        targetDate: target,
        remind: true,
        remindDaysBefore: 1,
        reminderKind: ReminderKind.push,
      );
      final expectedId = _idFor('countdown:${item.id}:due');

      notif.failScheduleOnceGeneric = true;
      await scheduler.syncCountdowns([item]);

      expect(notif.scheduled, isEmpty);

      notif.failScheduleOnceGeneric = false;
      await scheduler.syncCountdowns([item]);

      expect(notif.scheduled.map((entry) => entry['id']), contains(expectedId));
    });

    test('syncCountdowns 规则未变但 push pending 丢失时会重新注册', () async {
      final target = DateTime.now().add(const Duration(days: 7));
      final item = CountdownItem(
        id: 'countdown-pending-lost',
        title: '通知倒数队列丢失',
        targetDate: target,
        remind: true,
        remindDaysBefore: 1,
        reminderKind: ReminderKind.push,
      );
      final expectedId = _idFor('countdown:${item.id}:due');

      await scheduler.syncCountdowns([item]);
      expect(notif.scheduled.map((entry) => entry['id']), [expectedId]);
      expect(notif.pending, contains(expectedId));

      notif.pending.remove(expectedId);
      await scheduler.syncCountdowns([item]);

      expect(notif.cancelled, contains(expectedId));
      expect(
        notif.scheduled.where((entry) => entry['id'] == expectedId),
        hasLength(2),
      );
      expect(notif.pending, contains(expectedId));
    });

    test('syncCountdowns 切换提醒方式会取消旧通道后重新注册', () async {
      final target = DateTime.now().add(const Duration(days: 7));
      final push = CountdownItem(
        id: 'countdown-switch',
        title: '切换倒数日',
        targetDate: target,
        remind: true,
        remindDaysBefore: 1,
        reminderKind: ReminderKind.push,
      );
      final alarmItem = push.copyWith(reminderKind: ReminderKind.alarm);
      final expectedId = _idFor('countdown:${push.id}:due');

      await scheduler.syncCountdowns([push]);
      await scheduler.syncCountdowns([alarmItem]);

      expect(notif.cancelled, contains(expectedId));
      expect(alarm.cancelled, contains(expectedId));
      expect(popup.cancelled, contains(expectedId));
      expect(alarm.scheduled.map((item) => item['id']), contains(expectedId));
    });

    test('syncTodos 按通知、弹出框、闹钟、邮件和关闭五种提醒方式分支调度', () async {
      final todo = TodoItem(
        id: 'todo-kind-routing',
        title: '提醒方式分支',
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'r-push',
              type: ReminderRuleType.dailyTime,
              kind: ReminderKind.push,
              hour: 9,
              minute: 0,
            ),
            ReminderRule(
              id: 'r-popup',
              type: ReminderRuleType.dailyTime,
              kind: ReminderKind.popup,
              hour: 10,
              minute: 0,
            ),
            ReminderRule(
              id: 'r-alarm',
              type: ReminderRuleType.dailyTime,
              kind: ReminderKind.alarm,
              hour: 11,
              minute: 0,
            ),
            ReminderRule(
              id: 'r-email',
              type: ReminderRuleType.dailyTime,
              kind: ReminderKind.email,
              hour: 12,
              minute: 0,
            ),
            ReminderRule(
              id: 'r-off',
              enabled: true,
              type: ReminderRuleType.dailyTime,
              kind: ReminderKind.off,
              hour: 13,
              minute: 0,
            ),
          ],
        ),
      );

      await scheduler.syncTodos([todo]);

      expect(notif.scheduled.map((item) => item['id']), [
        _idFor('todo:${todo.id}:r-push'),
      ]);
      expect(popup.scheduled.map((item) => item['id']), [
        _idFor('todo:${todo.id}:r-popup'),
      ]);
      expect(alarm.scheduled.map((item) => item['id']), [
        _idFor('todo:${todo.id}:r-alarm'),
      ]);
      expect(email.scheduled.map((item) => item['id']), [
        _idFor('todo:${todo.id}:r-email'),
      ]);
      expect(
        [
          ...notif.scheduled,
          ...popup.scheduled,
          ...alarm.scheduled,
          ...email.scheduled,
        ].map((item) => item['id']),
        isNot(contains(_idFor('todo:${todo.id}:r-off'))),
      );
    });

    test('syncTodos 通知、弹窗和闹钟都可切换为关闭并清理旧通道', () async {
      TodoItem item(List<ReminderKind> kinds) {
        return TodoItem(
          id: 'todo-disable-three-kinds',
          title: '关闭提醒方式',
          reminderPlan: ReminderPlan(
            enabled: true,
            rules: [
              ReminderRule(
                id: 'push-rule',
                type: ReminderRuleType.dailyTime,
                kind: kinds[0],
                hour: 8,
                minute: 0,
              ),
              ReminderRule(
                id: 'popup-rule',
                type: ReminderRuleType.dailyTime,
                kind: kinds[1],
                hour: 9,
                minute: 0,
              ),
              ReminderRule(
                id: 'alarm-rule',
                type: ReminderRuleType.dailyTime,
                kind: kinds[2],
                hour: 10,
                minute: 0,
              ),
            ],
          ),
        );
      }

      final enabled = item(const [
        ReminderKind.push,
        ReminderKind.popup,
        ReminderKind.alarm,
      ]);
      final disabled = item(const [
        ReminderKind.off,
        ReminderKind.off,
        ReminderKind.off,
      ]);
      final ids = [
        _idFor('todo:${enabled.id}:push-rule'),
        _idFor('todo:${enabled.id}:popup-rule'),
        _idFor('todo:${enabled.id}:alarm-rule'),
      ];

      await scheduler.syncTodos([enabled]);
      expect(notif.scheduled.map((entry) => entry['id']), [ids[0]]);
      expect(popup.scheduled.map((entry) => entry['id']), [ids[1]]);
      expect(alarm.scheduled.map((entry) => entry['id']), [ids[2]]);

      notif.scheduled.clear();
      popup.scheduled.clear();
      alarm.scheduled.clear();
      email.scheduled.clear();
      notif.cancelled.clear();
      alarm.cancelled.clear();
      popup.cancelled.clear();
      email.cancelled.clear();

      await scheduler.syncTodos([disabled]);

      expect(notif.scheduled, isEmpty);
      expect(popup.scheduled, isEmpty);
      expect(alarm.scheduled, isEmpty);
      expect(email.scheduled, isEmpty);
      expect(notif.cancelled, containsAll(ids));
      expect(popup.cancelled, containsAll(ids));
      expect(alarm.cancelled, containsAll(ids));
      expect(email.cancelled, containsAll(ids));
      for (final id in ids) {
        expect(notif.pending, isNot(contains(id)));
        expect(alarm.pending, isNot(contains(id)));
      }
    });

    test('syncTodos 每周重复提醒按通知、弹出框、闹钟和关闭分支路由', () async {
      final todo = TodoItem(
        id: 'todo-weekly-kind-routing',
        title: '每周提醒方式分支',
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'weekly-push',
              type: ReminderRuleType.weeklyTime,
              kind: ReminderKind.push,
              hour: 8,
              minute: 0,
              weekdays: const [1, 3],
            ),
            ReminderRule(
              id: 'weekly-popup',
              type: ReminderRuleType.weeklyTime,
              kind: ReminderKind.popup,
              hour: 9,
              minute: 0,
              weekdays: const [2],
            ),
            ReminderRule(
              id: 'weekly-alarm',
              type: ReminderRuleType.weeklyTime,
              kind: ReminderKind.alarm,
              hour: 10,
              minute: 0,
              weekdays: const [4, 5],
            ),
            ReminderRule(
              id: 'weekly-off',
              enabled: true,
              type: ReminderRuleType.weeklyTime,
              kind: ReminderKind.off,
              hour: 11,
              minute: 0,
              weekdays: const [6],
            ),
          ],
        ),
      );
      final pushId = _idFor('todo:${todo.id}:weekly-push');
      final popupId = _idFor('todo:${todo.id}:weekly-popup');
      final alarmId = _idFor('todo:${todo.id}:weekly-alarm');
      final offId = _idFor('todo:${todo.id}:weekly-off');

      await scheduler.syncTodos([todo]);

      expect(notif.scheduled.map((entry) => entry['id']), [pushId]);
      expect(popup.scheduled.map((entry) => entry['id']), [popupId]);
      expect(alarm.scheduled.map((entry) => entry['id']), [alarmId]);
      expect(
        notif.pending,
        containsAll([_subId(pushId, 1), _subId(pushId, 3)]),
      );
      expect(
        alarm.pending,
        containsAll([_subId(alarmId, 4), _subId(alarmId, 5)]),
      );
      expect(notif.pending.intersection(alarm.pending), isEmpty);
      expect(
        [
          ...notif.scheduled,
          ...popup.scheduled,
          ...alarm.scheduled,
        ].map((entry) => entry['id']),
        isNot(contains(offId)),
      );
    });

    test('syncTodos 同一 rule 在通知、弹出框和闹钟之间切换只保留当前通道', () async {
      final due = DateTime.now().add(const Duration(days: 1));
      TodoItem item(ReminderKind kind) {
        return TodoItem(
          id: 'todo-kind-switch-matrix',
          title: '提醒方式互切',
          dueDate: due,
          reminderPlan: ReminderPlan(
            enabled: true,
            rules: [
              ReminderRule(
                id: 'same-rule',
                type: ReminderRuleType.absolute,
                kind: kind,
                hour: due.hour,
                minute: due.minute,
              ),
            ],
          ),
        );
      }

      final expectedId = _idFor('todo:todo-kind-switch-matrix:same-rule');

      await scheduler.syncTodos([item(ReminderKind.push)]);
      expect(notif.scheduled.map((entry) => entry['id']), [expectedId]);

      await scheduler.syncTodos([item(ReminderKind.popup)]);
      expect(notif.cancelled, contains(expectedId));
      expect(alarm.cancelled, contains(expectedId));
      expect(popup.scheduled.map((entry) => entry['id']), [expectedId]);
      expect(notif.pending, isNot(contains(expectedId)));

      await scheduler.syncTodos([item(ReminderKind.alarm)]);
      expect(popup.cancelled, contains(expectedId));
      expect(alarm.scheduled.map((entry) => entry['id']), [expectedId]);

      await scheduler.syncTodos([item(ReminderKind.push)]);
      expect(alarm.cancelled, contains(expectedId));
      expect(
        notif.scheduled.where((entry) => entry['id'] == expectedId),
        hasLength(2),
      );
      expect(
        popup.scheduled.where((entry) => entry['id'] == expectedId),
        hasLength(1),
      );
      expect(
        alarm.scheduled.where((entry) => entry['id'] == expectedId),
        hasLength(1),
      );
      expect(notif.pending, contains(expectedId));
      expect(alarm.pending, isNot(contains(expectedId)));
    });

    test('syncTodos 规则未变但 push pending 丢失时会重新注册', () async {
      final due = DateTime.now().add(const Duration(days: 1));
      final todo = TodoItem(
        id: 'todo-push-pending-lost',
        title: '通知队列丢失',
        dueDate: due,
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'r-push',
              type: ReminderRuleType.absolute,
              kind: ReminderKind.push,
              hour: due.hour,
              minute: due.minute,
            ),
          ],
        ),
      );
      final expectedId = _idFor('todo:${todo.id}:r-push');

      await scheduler.syncTodos([todo]);
      expect(notif.scheduled.map((entry) => entry['id']), [expectedId]);

      notif.pending.remove(expectedId);
      await scheduler.syncTodos([todo]);

      expect(notif.cancelled, contains(expectedId));
      expect(
        notif.scheduled.where((entry) => entry['id'] == expectedId),
        hasLength(2),
      );
      expect(notif.pending, contains(expectedId));
    });

    test('syncTodos 规则未变但 push pending 查询失败时会重新注册并记录诊断', () async {
      final due = DateTime.now().add(const Duration(days: 1));
      final todo = TodoItem(
        id: 'todo-push-pending-probe-failed',
        title: '通知队列查询失败',
        dueDate: due,
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'r-push',
              type: ReminderRuleType.absolute,
              kind: ReminderKind.push,
              hour: due.hour,
              minute: due.minute,
            ),
          ],
        ),
      );
      final expectedId = _idFor('todo:${todo.id}:r-push');
      final expectedKey = 'todo:${todo.id}:r-push';

      await scheduler.syncTodos([todo]);
      expect(notif.scheduled.map((entry) => entry['id']), [expectedId]);

      notif.failPendingIds = true;
      await scheduler.syncTodos([todo]);

      expect(notif.cancelled, contains(expectedId));
      expect(
        notif.scheduled.where((entry) => entry['id'] == expectedId),
        hasLength(2),
      );
      expect(notif.issues, hasLength(1));
      expect(notif.issues.single['title'], '普通通知状态无法确认');
      expect(notif.issues.single['message'], contains('系统待触发队列查询失败'));
      expect(
        notif.issues.single['message'],
        contains('forced notification pending query failure'),
      );
      expect(notif.issues.single['relatedId'], expectedKey);
      expect(notif.issues.single['blocking'], isFalse);
    });

    test('syncTodos 冷启动同步前清理当前 rule id，避免旧队列并存', () async {
      final due = DateTime.now().add(const Duration(days: 1));
      final todo = TodoItem(
        id: 'todo-cold-start-sweep',
        title: '冷启动清理',
        dueDate: due,
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'r-push',
              type: ReminderRuleType.absolute,
              kind: ReminderKind.push,
              hour: due.hour,
              minute: due.minute,
            ),
          ],
        ),
      );
      final expectedId = _idFor('todo:${todo.id}:r-push');

      final coldScheduler = ReminderScheduler(
        notif,
        alarm: alarm,
        popup: popup,
        email: email,
        registry: registry,
      );
      await coldScheduler.syncTodos([todo]);

      expect(notif.cancelled, contains(expectedId));
      expect(alarm.cancelled, contains(expectedId));
      expect(popup.cancelled, contains(expectedId));
      expect(email.cancelled, contains(expectedId));
      expect(notif.scheduled.map((entry) => entry['id']), [expectedId]);
    });

    test('syncTodos 冷启动会清理已持久化的旧 rule id', () async {
      final due = DateTime.now().add(const Duration(days: 1));
      final original = TodoItem(
        id: 'todo-cold-start-old-rule',
        title: '旧规则清理',
        dueDate: due,
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'old-rule',
              type: ReminderRuleType.absolute,
              kind: ReminderKind.push,
              hour: due.hour,
              minute: due.minute,
            ),
          ],
        ),
      );
      final edited = TodoItem(
        id: original.id,
        title: original.title,
        dueDate: due,
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'new-rule',
              type: ReminderRuleType.absolute,
              kind: ReminderKind.push,
              hour: due.hour,
              minute: due.minute,
            ),
          ],
        ),
      );
      final oldId = _idFor('todo:${original.id}:old-rule');
      final newId = _idFor('todo:${edited.id}:new-rule');

      await scheduler.syncTodos([original]);
      final coldScheduler = ReminderScheduler(
        notif,
        alarm: alarm,
        popup: popup,
        email: email,
        registry: registry,
      );
      await coldScheduler.syncTodos([edited]);

      expect(notif.cancelled, contains(oldId));
      expect(alarm.cancelled, contains(oldId));
      expect(popup.cancelled, contains(oldId));
      expect(email.cancelled, contains(oldId));
      expect(notif.scheduled.map((entry) => entry['id']), [oldId, newId]);
      expect(notif.pending, isNot(contains(oldId)));
      expect(notif.pending, contains(newId));
    });

    test('syncTodos 改规则时取消失败不会注册新提醒造成双响', () async {
      final due = DateTime.now().add(const Duration(days: 1));
      final todo = TodoItem(
        id: 'todo-cancel-failure-no-duplicate',
        title: '取消失败',
        dueDate: due,
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'r-push',
              type: ReminderRuleType.absolute,
              kind: ReminderKind.push,
              hour: due.hour,
              minute: due.minute,
            ),
          ],
        ),
      );
      final edited = todo.copyWith(
        title: '取消失败后不重放',
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'r-push',
              type: ReminderRuleType.absolute,
              kind: ReminderKind.alarm,
              hour: due.hour,
              minute: due.minute,
            ),
          ],
        ),
      );
      final expectedId = _idFor('todo:${todo.id}:r-push');

      await scheduler.syncTodos([todo]);
      notif.failCancel = true;
      await scheduler.syncTodos([edited]);

      expect(notif.cancelled, contains(expectedId));
      expect(alarm.scheduled, isEmpty);
      expect(
        notif.scheduled.where((entry) => entry['id'] == expectedId),
        hasLength(1),
      );
      expect(notif.issues, hasLength(1));
      expect(notif.issues.single['title'], '提醒交接失败');
      expect(notif.issues.single['message'], contains('旧提醒清理失败'));
      expect(
        notif.issues.single['relatedId'],
        'todo notification:${todo.id}:r-push',
      );
      expect(notif.issues.single['blocking'], isTrue);
    });

    test('syncTodos 每周原生闹钟 base id pending 时不会重复重注册', () async {
      final todo = TodoItem(
        id: 'todo-native-weekly-base-pending',
        title: '原生每周闹钟',
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'weekly-alarm',
              type: ReminderRuleType.weeklyTime,
              kind: ReminderKind.alarm,
              hour: 8,
              minute: 30,
              weekdays: const [1, 3],
            ),
          ],
        ),
      );
      final expectedId = _idFor('todo:${todo.id}:weekly-alarm');

      await scheduler.syncTodos([todo]);
      expect(alarm.scheduled.map((entry) => entry['id']), [expectedId]);

      alarm.pending
        ..clear()
        ..add(expectedId);
      final scheduledBefore = alarm.scheduled.length;

      await scheduler.syncTodos([todo]);

      expect(alarm.scheduled, hasLength(scheduledBefore));
      expect(
        alarm.scheduled.where((entry) => entry['id'] == expectedId),
        hasLength(1),
      );
      expect(alarm.pending, contains(expectedId));
    });

    test('syncTodos 规则未变但每周闹钟 pending 丢失时会重新注册', () async {
      final todo = TodoItem(
        id: 'todo-alarm-pending-lost',
        title: '闹钟队列丢失',
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'weekly-alarm',
              type: ReminderRuleType.weeklyTime,
              kind: ReminderKind.alarm,
              hour: 8,
              minute: 30,
              weekdays: const [1, 3],
            ),
          ],
        ),
      );
      final expectedId = _idFor('todo:${todo.id}:weekly-alarm');
      final mondayId = _subId(expectedId, 1);
      final wednesdayId = _subId(expectedId, 3);

      await scheduler.syncTodos([todo]);
      expect(alarm.scheduled.map((entry) => entry['id']), [expectedId]);
      expect(alarm.pending, containsAll([mondayId, wednesdayId]));

      alarm.pending.remove(mondayId);
      await scheduler.syncTodos([todo]);

      expect(alarm.cancelled, contains(expectedId));
      expect(
        alarm.scheduled.where((entry) => entry['id'] == expectedId),
        hasLength(2),
      );
      expect(alarm.pending, containsAll([mondayId, wednesdayId]));
    });

    test('syncTodos 闹钟规则未变时会清理残留普通通知，避免双弹', () async {
      final due = DateTime.now().add(const Duration(days: 1));
      final todo = TodoItem(
        id: 'todo-alarm-stale-push',
        title: '清理残留通知',
        dueDate: due,
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'r-alarm',
              type: ReminderRuleType.absolute,
              kind: ReminderKind.alarm,
              hour: due.hour,
              minute: due.minute,
            ),
          ],
        ),
      );
      final expectedId = _idFor('todo:${todo.id}:r-alarm');

      await scheduler.syncTodos([todo]);
      expect(alarm.scheduled.map((entry) => entry['id']), [expectedId]);

      notif.pending.add(expectedId);
      alarm.scheduled.clear();
      await scheduler.syncTodos([todo]);

      expect(alarm.scheduled, isEmpty);
      expect(notif.cancelled, contains(expectedId));
      expect(notif.pending, isNot(contains(expectedId)));
      expect(alarm.pending, contains(expectedId));
    });

    test('syncTodos 每周闹钟规则未变时会清理旧版普通通知子 id，避免双弹', () async {
      final todo = TodoItem(
        id: 'todo-weekly-alarm-stale-legacy-push',
        title: '清理每周旧通知',
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'weekly-alarm',
              type: ReminderRuleType.weeklyTime,
              kind: ReminderKind.alarm,
              hour: 8,
              minute: 30,
              weekdays: const [1, 3],
            ),
          ],
        ),
      );
      final expectedId = _idFor('todo:${todo.id}:weekly-alarm');
      final mondayId = _subId(expectedId, 1);
      final wednesdayId = _subId(expectedId, 3);
      final legacyMondayId = _legacySubId(expectedId, 1);

      await scheduler.syncTodos([todo]);
      expect(alarm.scheduled.map((entry) => entry['id']), [expectedId]);
      expect(alarm.pending, containsAll([mondayId, wednesdayId]));

      notif.pending.add(legacyMondayId);
      alarm.scheduled.clear();
      await scheduler.syncTodos([todo]);

      expect(alarm.scheduled, isEmpty);
      expect(notif.cancelled, contains(legacyMondayId));
      expect(notif.pending, isNot(contains(legacyMondayId)));
      expect(alarm.pending, containsAll([mondayId, wednesdayId]));
    });

    test('syncTodos 每周闹钟规则未变时会清理当前普通通知子 id，避免双弹', () async {
      final todo = TodoItem(
        id: 'todo-weekly-alarm-stale-current-push',
        title: '清理每周当前通知',
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'weekly-alarm',
              type: ReminderRuleType.weeklyTime,
              kind: ReminderKind.alarm,
              hour: 8,
              minute: 30,
              weekdays: const [1, 3],
            ),
          ],
        ),
      );
      final expectedId = _idFor('todo:${todo.id}:weekly-alarm');
      final mondayId = _subId(expectedId, 1);
      final wednesdayId = _subId(expectedId, 3);

      await scheduler.syncTodos([todo]);
      expect(alarm.scheduled.map((entry) => entry['id']), [expectedId]);
      expect(alarm.pending, containsAll([mondayId, wednesdayId]));

      notif.pending.add(mondayId);
      alarm.scheduled.clear();
      await scheduler.syncTodos([todo]);

      expect(alarm.scheduled, isEmpty);
      expect(notif.cancelled, contains(mondayId));
      expect(notif.pending, isNot(contains(mondayId)));
      expect(alarm.pending, containsAll([mondayId, wednesdayId]));
    });

    test('syncTodos 普通通知规则未变时会清理残留闹钟，避免双弹', () async {
      final due = DateTime.now().add(const Duration(days: 1));
      final todo = TodoItem(
        id: 'todo-push-stale-alarm',
        title: '清理残留闹钟',
        dueDate: due,
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'r-push',
              type: ReminderRuleType.absolute,
              kind: ReminderKind.push,
              hour: due.hour,
              minute: due.minute,
            ),
          ],
        ),
      );
      final expectedId = _idFor('todo:${todo.id}:r-push');

      await scheduler.syncTodos([todo]);
      expect(notif.scheduled.map((entry) => entry['id']), [expectedId]);

      alarm.pending.add(expectedId);
      notif.scheduled.clear();
      await scheduler.syncTodos([todo]);

      expect(notif.scheduled, isEmpty);
      expect(alarm.cancelled, contains(expectedId));
      expect(alarm.pending, isNot(contains(expectedId)));
      expect(notif.pending, contains(expectedId));
    });

    test('syncTodos 弹出框规则未变时会清理残留通知和闹钟，避免双弹', () async {
      final due = DateTime.now().add(const Duration(days: 1));
      final todo = TodoItem(
        id: 'todo-popup-stale-peers',
        title: '清理弹窗残留',
        dueDate: due,
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'r-popup',
              type: ReminderRuleType.absolute,
              kind: ReminderKind.popup,
              hour: due.hour,
              minute: due.minute,
            ),
          ],
        ),
      );
      final expectedId = _idFor('todo:${todo.id}:r-popup');

      await scheduler.syncTodos([todo]);
      expect(popup.scheduled.map((entry) => entry['id']), [expectedId]);

      notif.pending.add(expectedId);
      alarm.pending.add(expectedId);
      popup.scheduled.clear();
      await scheduler.syncTodos([todo]);

      expect(popup.scheduled, isEmpty);
      expect(notif.cancelled, contains(expectedId));
      expect(alarm.cancelled, contains(expectedId));
      expect(notif.pending, isNot(contains(expectedId)));
      expect(alarm.pending, isNot(contains(expectedId)));
    });

    test('syncTodos 邮件一次性调度失败时不缓存成功状态，恢复后重试', () async {
      final due = DateTime.now().add(const Duration(hours: 2));
      final todo = TodoItem(
        id: 'todo-email-once-retry',
        title: '邮件提醒',
        dueDate: due,
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'r-email',
              type: ReminderRuleType.absolute,
              kind: ReminderKind.email,
              hour: due.hour,
              minute: due.minute,
            ),
          ],
        ),
      );

      email.failOnce = true;
      await scheduler.syncTodos([todo]);

      expect(email.scheduled, isEmpty);

      email.failOnce = false;
      await scheduler.syncTodos([todo]);

      expect(email.scheduled.map((entry) => entry['id']), [
        _idFor('todo:${todo.id}:r-email'),
      ]);
    });

    test('syncTodos 邮件重复调度失败时不缓存成功状态，恢复后重试', () async {
      final todo = TodoItem(
        id: 'todo-email-repeating-retry',
        title: '邮件重复提醒',
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'r-email',
              type: ReminderRuleType.dailyTime,
              kind: ReminderKind.email,
              hour: 9,
              minute: 30,
            ),
          ],
        ),
      );

      email.failRepeating = true;
      await scheduler.syncTodos([todo]);

      expect(email.scheduled, isEmpty);

      email.failRepeating = false;
      await scheduler.syncTodos([todo]);

      expect(email.scheduled.map((entry) => entry['id']), [
        _idFor('todo:${todo.id}:r-email'),
      ]);
    });

    test('syncAnniversaries 邮件调度失败时不缓存成功状态，恢复后重试', () async {
      final a = Anniversary(
        id: 'ann-email-retry',
        title: '邮件纪念',
        originDate: DateTime.now().add(const Duration(days: 30)),
        type: AnniversaryType.memorial,
        remind: true,
        remindDaysBefore: 1,
        remindHour: 9,
        reminderKind: ReminderKind.email,
      );

      email.failOnce = true;
      await scheduler.syncAnniversaries([a]);

      expect(email.scheduled, isEmpty);

      email.failOnce = false;
      await scheduler.syncAnniversaries([a]);

      expect(email.scheduled.map((entry) => entry['id']), [
        _anniversaryPopupId(a.id),
      ]);
    });

    test('邮件取消失败不会中断其他通道清理', () async {
      final todo = TodoItem(
        id: 'todo-email-cancel-failure',
        title: '邮件取消失败',
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'r-email',
              type: ReminderRuleType.dailyTime,
              kind: ReminderKind.email,
              hour: 9,
              minute: 0,
            ),
          ],
        ),
      );

      await scheduler.syncTodos([todo]);
      email.failCancel = true;

      await scheduler.syncTodos(const []);

      expect(notif.cancelled, contains(_idFor('todo:${todo.id}:r-email')));
      expect(alarm.cancelled, contains(_idFor('todo:${todo.id}:r-email')));
      expect(popup.cancelled, contains(_idFor('todo:${todo.id}:r-email')));
    });

    test('syncGoals 对非 active 状态不调度', () async {
      final g = GoalItem(id: 'g1', title: '已完成目标', status: GoalStatus.achieved);
      await scheduler.syncGoals([g]);
      expect(notif.scheduled, isEmpty);
      expect(alarm.scheduled, isEmpty);
    });

    test('syncGoals 同一时间重复提醒只保留最高优先级通道', () async {
      final target = DateTime.now().add(const Duration(days: 1));
      final goal = GoalItem(
        id: 'goal-duplicate-kind-delivery',
        title: '目标双通道',
        targetDate: target,
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'goal-email',
              type: ReminderRuleType.relativeToDue,
              kind: ReminderKind.email,
              hour: target.hour,
              minute: target.minute,
              offsetMinutes: 0,
            ),
            ReminderRule(
              id: 'goal-push',
              type: ReminderRuleType.absolute,
              kind: ReminderKind.push,
              hour: target.hour,
              minute: target.minute,
            ),
          ],
        ),
      );

      await scheduler.syncGoals([goal]);

      expect(email.scheduled, isEmpty);
      expect(notif.scheduled.map((entry) => entry['id']), [
        _idFor('goal:${goal.id}:goal-push'),
      ]);
    });

    test('syncGoals 同一时间通知和闹钟只保留闹钟', () async {
      final target = DateTime.now().add(const Duration(days: 1));
      final goal = GoalItem(
        id: 'goal-duplicate-alarm-delivery',
        title: '目标闹钟优先',
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'goal-push',
              type: ReminderRuleType.absolute,
              kind: ReminderKind.push,
              hour: target.hour,
              minute: target.minute,
            ),
            ReminderRule(
              id: 'goal-alarm',
              type: ReminderRuleType.absolute,
              kind: ReminderKind.alarm,
              hour: target.hour,
              minute: target.minute,
              fullScreen: true,
            ),
          ],
        ),
      );

      await scheduler.syncGoals([goal]);

      expect(notif.scheduled, isEmpty);
      expect(alarm.scheduled.map((entry) => entry['id']), [
        _idFor('goal:${goal.id}:goal-alarm'),
      ]);
    });

    test('syncGoals 按弹出框和关闭提醒分支调度', () async {
      final target = DateTime.now().add(const Duration(days: 1));
      final goal = GoalItem(
        id: 'goal-popup-off-routing',
        title: '目标弹窗提醒',
        targetDate: target,
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'goal-popup',
              type: ReminderRuleType.absolute,
              kind: ReminderKind.popup,
              hour: target.hour,
              minute: target.minute,
            ),
            ReminderRule(
              id: 'goal-off',
              enabled: true,
              type: ReminderRuleType.absolute,
              kind: ReminderKind.off,
              hour: target.hour,
              minute: target.minute,
            ),
          ],
        ),
      );
      final popupId = _idFor('goal:${goal.id}:goal-popup');
      final offId = _idFor('goal:${goal.id}:goal-off');

      await scheduler.syncGoals([goal]);

      expect(popup.scheduled.map((entry) => entry['id']), [popupId]);
      expect(notif.scheduled, isEmpty);
      expect(alarm.scheduled, isEmpty);
      expect(email.scheduled, isEmpty);
      expect(
        [
          ...notif.scheduled,
          ...popup.scheduled,
          ...alarm.scheduled,
          ...email.scheduled,
        ].map((entry) => entry['id']),
        isNot(contains(offId)),
      );
    });

    test('syncGoals 从 popup 切到 off 会清理旧弹窗提醒', () async {
      final target = DateTime.now().add(const Duration(days: 1));
      GoalItem goal(ReminderKind kind) {
        return GoalItem(
          id: 'goal-popup-off-switch',
          title: '目标提醒切换',
          targetDate: target,
          reminderPlan: ReminderPlan(
            enabled: true,
            rules: [
              ReminderRule(
                id: 'goal-reminder',
                type: ReminderRuleType.absolute,
                kind: kind,
                hour: target.hour,
                minute: target.minute,
              ),
            ],
          ),
        );
      }

      final expectedId = _idFor('goal:goal-popup-off-switch:goal-reminder');

      await scheduler.syncGoals([goal(ReminderKind.popup)]);
      expect(popup.scheduled.map((entry) => entry['id']), [expectedId]);

      await scheduler.syncGoals([goal(ReminderKind.off)]);

      expect(popup.cancelled, contains(expectedId));
      expect(notif.cancelled, contains(expectedId));
      expect(alarm.cancelled, contains(expectedId));
      expect(email.cancelled, contains(expectedId));
    });

    test('syncGoals 通知权限异常但闹钟已入队时不降级普通通知避免双弹', () async {
      alarm
        ..failFullScreenWithNotificationPermission = true
        ..rememberFullScreenPendingBeforeNotificationPermission = true;
      final target = DateTime.now().add(const Duration(days: 1));
      final goal = GoalItem(
        id: 'goal-notification-permission-partial-no-fallback',
        title: '目标提醒',
        targetDate: target,
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'goal-alarm',
              type: ReminderRuleType.absolute,
              kind: ReminderKind.alarm,
              hour: target.hour,
              minute: target.minute,
              fullScreen: true,
            ),
          ],
        ),
      );
      final expectedId = _idFor('goal:${goal.id}:goal-alarm');

      await scheduler.syncGoals([goal]);

      expect(alarm.scheduled, isEmpty);
      expect(notif.scheduled, isEmpty);
      expect(alarm.pending, contains(expectedId));
    });
  });
}
