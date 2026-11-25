// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/models/calendar_event.dart';
import 'package:duoyi/models/course_schedule.dart';
import 'package:duoyi/models/goal.dart';
import 'package:duoyi/models/habit.dart';
import 'package:duoyi/models/pomodoro.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/calendar_provider.dart';
import 'package:duoyi/providers/course_provider.dart';
import 'package:duoyi/providers/notification_service.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/holiday_calendar.dart';
import 'package:duoyi/services/local_notifications_io.dart';
import 'package:duoyi/services/notification_action_envelope.dart';
import 'package:duoyi/services/reminder_scheduler.dart';
import 'package:duoyi/services/reminder_sinks.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class _TestNotifSink
    implements
        ReminderNotificationSink,
        ReminderNotificationScheduleResultSink,
        ReminderPendingSink,
        ReminderScheduleIssueSink {
  final List<Map<String, Object?>> scheduled = [];
  final List<int> cancelled = [];
  final Set<int> pending = {};
  int pendingIdsCalls = 0;

  static int _idFor(String key) {
    var h = 0;
    for (final c in key.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return h;
  }

  static int _subId(int base, int weekday) =>
      ((base ^ (weekday * 0x9e3779b1)) & 0x7fffffff);

  @override
  Future<bool> scheduleOnceWithResult({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
  }) async {
    await scheduleOnce(
      id: id,
      title: title,
      body: body,
      when: when,
      payload: payload,
    );
    return true;
  }

  @override
  Future<bool> scheduleDailyWithResult({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    List<int>? weekdays,
    String? payload,
  }) async {
    await scheduleDaily(
      id: id,
      title: title,
      body: body,
      hour: hour,
      minute: minute,
      weekdays: weekdays,
      payload: payload,
    );
    return true;
  }

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
    scheduled.add({
      'kind': 'daily',
      'id': id,
      'title': title,
      'body': body,
      'hour': hour,
      'minute': minute,
      'weekdays': weekdays == null ? null : List<int>.of(weekdays),
      'payload': payload,
    });
    if (weekdays == null || weekdays.isEmpty) {
      pending.add(id);
    } else {
      for (final day in weekdays) {
        pending.add(_subId(id, day));
      }
    }
  }

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
    pending.remove(id);
    for (var day = 1; day <= 7; day++) {
      pending.remove(_subId(id, day));
    }
  }

  @override
  Future<List<int>> pendingIds() async {
    pendingIdsCalls++;
    return pending.toList()..sort();
  }

  @override
  Future<void> cancelTodoReminder(String todoId) async {}

  @override
  Future<void> cancelHabitReminder(String habitId) async {
    final id = _idFor('habit_$habitId');
    pending.remove(id);
    for (var day = 1; day <= 7; day++) {
      pending.remove(_subId(id, day));
    }
  }

  @override
  Future<void> cancelAnniversary(String annId) async {}

  @override
  Future<void> scheduleHabitReminder({
    required String habitId,
    required String habitName,
    required int hour,
    required int minute,
    List<int>? weekdays,
  }) async {
    await scheduleDaily(
      id: _idFor('habit_$habitId'),
      title: '习惯提醒',
      body: habitName,
      hour: hour,
      minute: minute,
      weekdays: weekdays,
      payload: 'duoyi://habit/$habitId?confirm=1',
    );
  }

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
  void recordReminderScheduleIssue({
    required String title,
    required String message,
    DateTime? scheduledTime,
    String? relatedId,
    bool blocking = true,
  }) {}
}

class _TestAlarmSink implements ReminderAlarmSink, ReminderPendingSink {
  final List<Map<String, Object?>> scheduled = [];
  final List<int> cancelled = [];
  final Set<int> pending = {};

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
    pending.remove(id);
  }

  @override
  Future<List<int>> pendingIds() async => pending.toList()..sort();

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
      'kind': 'alarm',
      'id': id,
      'title': title,
      'body': body,
      'when': when,
      'payload': payload,
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
    scheduled.add({
      'kind': 'daily_alarm',
      'id': id,
      'hour': hour,
      'minute': minute,
      'weekdays': weekdays,
      'payload': payload,
    });
    pending.add(id);
  }
}

class _TestPopupSink implements ReminderPopupSink {
  final List<Map<String, Object?>> scheduled = [];

  @override
  Future<void> cancel(int id) async {}

  @override
  Future<void> scheduleOnce({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
  }) async {
    scheduled.add({'id': id, 'when': when, 'payload': payload});
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
    scheduled.add({
      'kind': 'popup_repeating',
      'id': id,
      'title': title,
      'body': body,
      'hour': hour,
      'minute': minute,
      'weekdays': weekdays == null ? null : List<int>.of(weekdays),
      'payload': payload,
    });
  }
}

class _TestEmailSink implements ReminderEmailSink {
  @override
  Future<void> cancel(int id) async {}

  @override
  Future<void> scheduleOnce({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
  }) async {}

  @override
  Future<void> scheduleRepeating({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    List<int>? weekdays,
    String? payload,
  }) async {}
}

class _CountingStore extends InMemorySharedPreferencesStore {
  _CountingStore([Map<String, Object>? initial])
    : super.withData(initial ?? const <String, Object>{});

  int runningSnapshotWrites = 0;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == 'flutter.${PomodoroProvider.runningSnapshotKey}') {
      runningSnapshotWrites++;
    }
    return super.setValue(valueType, key, value);
  }
}

class _RecordingNotificationService extends NotificationService {
  final List<({bool isFocus, String? taskName, DateTime when})>
  pomodoroEndScheduled = [];
  int pomodoroEndCancels = 0;

  @override
  Future<void> schedulePomodoroEndReminder({
    required bool isFocus,
    String? taskName,
    required DateTime when,
  }) async {
    pomodoroEndScheduled.add((
      isFocus: isFocus,
      taskName: taskName,
      when: when,
    ));
  }

  @override
  Future<void> cancelPomodoroEndReminder() async {
    pomodoroEndCancels++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferencesStorePlatform originalStore;

  setUp(() async {
    await AccountPreferenceWrites.drain();
    originalStore = SharedPreferencesStorePlatform.instance;
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() async {
    await AccountPreferenceWrites.drain();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    SharedPreferencesStorePlatform.instance = originalStore;
  });

  group('Course reminder scheduling', () {
    test(
      'syncCourses schedules next class minus reminderMinutes with duoyi://course/<id> and cancels when off',
      () async {
        final notif = _TestNotifSink();
        final scheduler = ReminderScheduler(
          notif,
          alarm: _TestAlarmSink(),
          email: _TestEmailSink(),
          popup: _TestPopupSink(),
        );
        final termStart = DateTime(2026, 3, 2); // Monday
        final settings = ScheduleSettings(
          termStart: termStart,
          totalWeeks: 20,
          firstSessionHour: 10,
          firstSessionMinute: 0,
        );
        final now = DateTime(2026, 3, 2, 8, 0);
        final course = CourseItem(
          id: 'course-math-1',
          name: '高等数学',
          location: 'A101',
          weekday: DateTime.monday,
          startSection: 1,
          weeks: const [1, 2],
          reminderMinutes: 15,
        );

        await scheduler.syncCourses([course], settings: settings, now: now);

        expect(notif.scheduled, hasLength(1));
        final call = notif.scheduled.single;
        expect(call['payload'], 'duoyi://course/course-math-1');
        expect(call['when'], DateTime(2026, 3, 2, 9, 45));
        expect(call['body'], contains('A101'));

        final offCourse = CourseItem(
          id: 'course-math-1',
          name: '高等数学',
          location: 'A101',
          weekday: DateTime.monday,
          startSection: 1,
          weeks: const [1, 2],
          reminderMinutes: 0,
        );
        await scheduler.syncCourses([offCourse], settings: settings, now: now);
        expect(notif.pending, isEmpty);
      },
    );

    test('CourseProvider attaches scheduler and syncs on add', () async {
      final notif = _TestNotifSink();
      final scheduler = ReminderScheduler(
        notif,
        alarm: _TestAlarmSink(),
        email: _TestEmailSink(),
        popup: _TestPopupSink(),
      );
      final provider = CourseProvider();
      addTearDown(provider.dispose);
      provider.scheduler = scheduler;

      final futureMonday = DateTime.now().add(const Duration(days: 7));
      final mondayStart = DateTime(
        futureMonday.year,
        futureMonday.month,
        futureMonday.day - (futureMonday.weekday - 1),
      );
      await provider.updateSettings(ScheduleSettings(termStart: mondayStart));
      await provider.add(
        CourseItem(
          id: 'c-sync',
          name: '线性代数',
          weekday: DateTime.wednesday,
          startSection: 2,
          weeks: const [1],
          reminderMinutes: 10,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(
        notif.scheduled.any((e) => e['payload'] == 'duoyi://course/c-sync'),
        isTrue,
      );
    });
  });

  group('Pomodoro OS background alarm & 1s tick dirty-flag', () {
    test(
      'PomodoroProvider schedules end reminder on start, cancels on pause/reset, and skips duplicate 1s tick encodes',
      () {
        fakeAsync((async) {
          final store = _CountingStore();
          SharedPreferencesStorePlatform.instance = store;
          final recorder = _RecordingNotificationService();
          final pomodoro = PomodoroProvider();
          pomodoro.attachNotifier(recorder);
          pomodoro.setConfig(PomodoroConfig(focusDuration: 25));
          async.flushMicrotasks();

          pomodoro.startIfIdle();
          async.flushMicrotasks();

          expect(recorder.pomodoroEndScheduled, hasLength(1));
          expect(recorder.pomodoroEndScheduled.single.isFocus, isTrue);
          expect(store.runningSnapshotWrites, 1);

          // Advance 5 x 1s ticks without metadata changes: zero extra writes.
          async.elapse(const Duration(seconds: 5));
          async.flushMicrotasks();
          expect(store.runningSnapshotWrites, 1);

          // Changing task name marks dirty and persists updated snapshot on tick.
          pomodoro.setTaskName('Write tests');
          async.elapse(const Duration(seconds: 1));
          async.flushMicrotasks();
          expect(store.runningSnapshotWrites, 2);

          // Pause cancels background OS reminder.
          pomodoro.toggleTimer();
          async.flushMicrotasks();
          expect(recorder.pomodoroEndCancels, greaterThanOrEqualTo(1));

          // Resume schedules again, reset cancels cleanly.
          pomodoro.toggleTimer();
          async.flushMicrotasks();
          expect(recorder.pomodoroEndScheduled, hasLength(3));
          final cancelsBeforeReset = recorder.pomodoroEndCancels;
          pomodoro.resetTimer();
          async.flushMicrotasks();
          expect(recorder.pomodoroEndCancels, greaterThan(cancelsBeforeReset));

          pomodoro.dispose();
        });
      },
    );
  });

  group('CalendarEvent reminders & CalendarProvider cache', () {
    test(
      'CalendarEvent reminderMinutes serializes backward-compatibly and syncs via ReminderScheduler',
      () async {
        final legacy = CalendarEvent.fromJson({
          'id': 'ev-legacy',
          'title': '旧日程',
          'date': '2026-08-01T00:00:00.000',
          'type': CalendarEventType.event.index,
        });
        expect(legacy.reminderMinutes, isNull);

        final eventDate = DateTime.now().add(const Duration(days: 3));
        final withReminder = CalendarEvent(
          id: 'ev-1',
          title: '项目评审',
          date: DateTime(eventDate.year, eventDate.month, eventDate.day),
          time: const TimeOfDay(hour: 15, minute: 30),
          type: CalendarEventType.event,
          color: Colors.blue,
          note: '会议室 302',
          reminderMinutes: 15,
        );
        final roundTrip = CalendarEvent.fromJson(withReminder.toJson());
        expect(roundTrip.reminderMinutes, 15);
        expect(roundTrip.copyWith(clearReminderMinutes: true).reminderMinutes, isNull);

        final notif = _TestNotifSink();
        final scheduler = ReminderScheduler(
          notif,
          alarm: _TestAlarmSink(),
          email: _TestEmailSink(),
          popup: _TestPopupSink(),
        );
        await scheduler.syncCalendarEvents([withReminder]);
        expect(notif.scheduled, hasLength(1));
        final scheduled = notif.scheduled.single;
        expect(
          scheduled['when'],
          DateTime(eventDate.year, eventDate.month, eventDate.day, 15, 15),
        );
        expect(scheduled['payload'], contains('duoyi://calendar?date='));
        expect(scheduled['payload'], contains('eventId=ev-1'));

        await scheduler.syncCalendarEvents([
          withReminder.copyWith(clearReminderMinutes: true),
        ]);
        expect(notif.pending, isEmpty);
      },
    );

    test(
      'CalendarProvider caches derived dateEventTypes/counts until mutation and syncs scheduler',
      () async {
        final notif = _TestNotifSink();
        final scheduler = ReminderScheduler(
          notif,
          alarm: _TestAlarmSink(),
          email: _TestEmailSink(),
          popup: _TestPopupSink(),
        );
        final provider = CalendarProvider();
        addTearDown(provider.dispose);
        provider.scheduler = scheduler;

        final tomorrow = DateTime.now().add(const Duration(days: 2));
        await provider.addLocalEvent(
          CalendarEvent(
            id: 'cal-1',
            title: '产品同步',
            date: DateTime(tomorrow.year, tomorrow.month, tomorrow.day),
            time: const TimeOfDay(hour: 10, minute: 0),
            type: CalendarEventType.event,
            color: Colors.blue,
            reminderMinutes: 5,
          ),
        );

        final t1 = provider.dateEventTypes;
        final t2 = provider.dateEventTypes;
        final c1 = provider.filteredDateEventCounts({CalendarEventType.event});
        final c2 = provider.filteredDateEventCounts({CalendarEventType.event});
        expect(t1, t2);
        expect(c1, c2);
        expect(notif.scheduled.any((e) => (e['payload'] as String).contains('cal-1')), isTrue);

        await provider.deleteLocalEvent('cal-1');
        expect(notif.pending, isEmpty);
        expect(provider.dateEventTypes, isEmpty);
      },
    );
  });

  group('Scale & Budget Cap (pendingIds cache + 380 active alarms)', () {
    test(
      'standalone syncTodos caches pendingIds once per sync instead of O(N) queries and supports incremental syncSingleTodo',
      () async {
        final notif = _TestNotifSink();
        final scheduler = ReminderScheduler(
          notif,
          alarm: _TestAlarmSink(),
          email: _TestEmailSink(),
          popup: _TestPopupSink(),
        );
        final base = DateTime.now().add(const Duration(days: 2));
        final todos = List.generate(
          40,
          (i) => TodoItem(
            id: 't-$i',
            title: 'Task $i',
            dueDate: base.add(Duration(minutes: i)),
            reminderPlan: ReminderPlan(
              enabled: true,
              rules: [
                ReminderRule(
                  id: 'r-$i',
                  type: ReminderRuleType.absolute,
                  kind: ReminderKind.push,
                  hour: 10,
                  minute: 0,
                ),
              ],
            ),
          ),
        );

        await scheduler.syncTodos(todos);
        expect(notif.pending, hasLength(40));

        // Second sync with unchanged items uses at most 1 pendingIds() call total.
        notif.pendingIdsCalls = 0;
        await scheduler.syncTodos(todos);
        expect(notif.pendingIdsCalls, lessThanOrEqualTo(1));

        // Incremental single todo update only modifies that todo.
        final updated0 = todos.first.copyWith(isCompleted: true);
        await scheduler.syncSingleTodo(updated0);
        expect(notif.pending, hasLength(39));
      },
    );

    test(
      'enforces 380-alarm budget prioritizing nearest upcoming reminders and evicts farthest when closer item arrives',
      () async {
        final notif = _TestNotifSink();
        final scheduler = ReminderScheduler(
          notif,
          alarm: _TestAlarmSink(),
          email: _TestEmailSink(),
          popup: _TestPopupSink(),
        );
        final start = DateTime.now().add(const Duration(days: 1));
        final todos = List.generate(
          420,
          (i) => TodoItem(
            id: 'b-$i',
            title: 'Budget $i',
            dueDate: DateTime(
              start.year,
              start.month,
              start.day + i + 1,
            ),
            reminderPlan: ReminderPlan(
              enabled: true,
              rules: [
                ReminderRule(
                  id: 'rb-$i',
                  type: ReminderRuleType.absolute,
                  kind: ReminderKind.push,
                  hour: 9,
                  minute: 0,
                ),
              ],
            ),
          ),
        );

        await scheduler.syncTodos(todos);
        expect(notif.pending.length, ReminderScheduler.maxActiveAlarms);
        expect(scheduler.debugActiveBudgetCount, ReminderScheduler.maxActiveAlarms);

        final firstPayload = 'duoyi://todo/b-0';
        final lastPayload = 'duoyi://todo/b-419';
        expect(notif.scheduled.any((e) => e['payload'] == firstPayload), isTrue);
        expect(notif.scheduled.any((e) => e['payload'] == lastPayload), isFalse);

        // Add urgent todo earlier than all 380 buffered items -> evicts farthest (b-379).
        final urgentWhen = DateTime.now().add(const Duration(hours: 2));
        final urgent = TodoItem(
          id: 'urgent',
          title: 'Urgent',
          dueDate: urgentWhen,
          reminderPlan: ReminderPlan(
            enabled: true,
            rules: [
              ReminderRule(
                id: 'r-urgent',
                type: ReminderRuleType.absolute,
                kind: ReminderKind.push,
                hour: urgentWhen.hour,
                minute: urgentWhen.minute,
              ),
            ],
          ),
        );
        await scheduler.syncSingleTodo(urgent);
        expect(notif.pending.length, ReminderScheduler.maxActiveAlarms);
        expect(
          notif.scheduled.any((e) => e['payload'] == 'duoyi://todo/urgent'),
          isTrue,
        );
      },
    );
  });

  group('Snooze metadata, rich actions & headless background callback', () {
    test(
      'preserves title/body on snooze actions, routes multi-interval snooze & habit checkin, and executes headless todo completion safely',
      () async {
        const owner = 'regression-owner-A';
        SharedPreferences.setMockInitialValues(<String, Object>{
          AccountLocalDataCleaner.accountDataOwnerKey: owner,
          'flutter.todos': jsonEncode([
            TodoItem(id: 'todo-bg-1', title: '交报告').toJson(),
          ]),
          'flutter.habits': jsonEncode([
            Habit(id: 'habit-bg-1', name: '喝水').toJson(),
          ]),
        });

        final local = LocalNotifications.instance;
        const notifId = 515;
        const todoPayload = 'duoyi://todo/todo-bg-1';
        await local.recordScheduledMetadata(
          id: notifId,
          title: '待办到期',
          body: '交报告',
          payload: todoPayload,
        );
        final signed = await NotificationActionEnvelope.signPayload(
          notifId,
          todoPayload,
          actions: const [
            'todo_complete_todo-bg-1',
            'todo_snooze_todo-bg-1',
            'todo_snooze_15m',
            'todo_snooze_60m',
            'habit_checkin_habit-bg-1',
          ],
        );
        expect(signed, isNotNull);

        // Snooze preserves title & body from metadata when present.
        final snooze5 = await local.payloadForNotificationResponse(
          NotificationResponse(
            id: notifId,
            payload: signed,
            actionId: 'todo_snooze_todo-bg-1',
            notificationResponseType:
                NotificationResponseType.selectedNotificationAction,
          ),
        );
        expect(snooze5, isNotNull);
        final snooze5Uri = Uri.parse(snooze5!);
        expect(snooze5Uri.host, 'snooze');
        expect(snooze5Uri.queryParameters['delay'], '5');
        expect(snooze5Uri.queryParameters['title'], '待办到期');
        expect(snooze5Uri.queryParameters['body'], '交报告');

        final snooze15 = await local.payloadForNotificationResponse(
          NotificationResponse(
            id: notifId,
            payload: signed,
            actionId: 'todo_snooze_15m',
            notificationResponseType:
                NotificationResponseType.selectedNotificationAction,
          ),
        );
        expect(Uri.parse(snooze15!).queryParameters['delay'], '15');

        final snooze60 = await local.payloadForNotificationResponse(
          NotificationResponse(
            id: notifId,
            payload: signed,
            actionId: 'todo_snooze_60m',
            notificationResponseType:
                NotificationResponseType.selectedNotificationAction,
          ),
        );
        expect(Uri.parse(snooze60!).queryParameters['delay'], '60');

        final habitCheckin = await local.payloadForNotificationResponse(
          NotificationResponse(
            id: notifId,
            payload: signed,
            actionId: 'habit_checkin_habit-bg-1',
            notificationResponseType:
                NotificationResponseType.selectedNotificationAction,
          ),
        );
        expect(habitCheckin, 'duoyi://action/checkin_habit?id=habit-bg-1');

        // Unsigned/tampered background callback is rejected without mutating todos.
        await local.handleBackgroundNotificationResponse(
          const NotificationResponse(
            id: notifId,
            payload: 'duoyi://todo/todo-bg-1',
            actionId: 'todo_complete_todo-bg-1',
            notificationResponseType:
                NotificationResponseType.selectedNotificationAction,
          ),
        );
        final beforePrefs = await SharedPreferences.getInstance();
        expect(
          (jsonDecode(beforePrefs.getString('todos')!).single
              as Map<String, dynamic>)['isCompleted'],
          isNot(true),
        );

        // Headless completion updates persisted todos & habits without foreground launch.
        await local.handleBackgroundNotificationResponse(
          NotificationResponse(
            id: notifId,
            payload: signed,
            actionId: 'todo_complete_todo-bg-1',
            notificationResponseType:
                NotificationResponseType.selectedNotificationAction,
          ),
        );
        await local.handleBackgroundNotificationResponse(
          NotificationResponse(
            id: notifId,
            payload: signed,
            actionId: 'habit_checkin_habit-bg-1',
            notificationResponseType:
                NotificationResponseType.selectedNotificationAction,
          ),
        );

        final prefs = await SharedPreferences.getInstance();
        final todosJson =
            jsonDecode(prefs.getString('todos')!) as List<dynamic>;
        expect(
          (todosJson.single as Map<String, dynamic>)['isCompleted'],
          isTrue,
        );
        final habitsJson =
            jsonDecode(prefs.getString('habits')!) as List<dynamic>;
        final completions =
            (habitsJson.single as Map<String, dynamic>)['completions']
                as Map<String, dynamic>;
        expect(completions.values.first, 1);
      },
    );
  });

  group('Quiet Hours policy & scheduler deferral', () {
    test(
      'QuietHoursPolicy handles midnight wrap & local wall-clock end, and PreferencesProvider persists settings',
      () async {
        const policy = QuietHoursPolicy(
          enabled: true,
          startMinutes: 22 * 60,
          endMinutes: 7 * 60,
          allowAlarms: true,
          deferUntilEnd: true,
        );

        expect(policy.isWithinQuietHours(DateTime(2026, 6, 1, 22, 0)), isTrue);
        expect(policy.isWithinQuietHours(DateTime(2026, 6, 2, 3, 15)), isTrue);
        expect(policy.isWithinQuietHours(DateTime(2026, 6, 2, 6, 59)), isTrue);
        expect(policy.isWithinQuietHours(DateTime(2026, 6, 2, 7, 0)), isFalse);
        expect(policy.isWithinQuietHours(DateTime(2026, 6, 1, 21, 59)), isFalse);
        expect(
          policy.nextQuietEndLocal(DateTime(2026, 6, 1, 23, 30)),
          DateTime(2026, 6, 2, 7, 0),
        );
        expect(
          policy.nextQuietEndLocal(DateTime(2026, 6, 2, 2, 15)),
          DateTime(2026, 6, 2, 7, 0),
        );

        final prefsProvider = PreferencesProvider();
        addTearDown(prefsProvider.dispose);
        await prefsProvider.setQuietHoursEnabled(true);
        await prefsProvider.setQuietHoursWindow(
          23 * 60,
          6 * 60 + 30,
        );
        await prefsProvider.setQuietHoursAllowAlarms(false);
        await prefsProvider.setQuietHoursDeferUntilEnd(true);

        final reloaded = PreferencesProvider();
        addTearDown(reloaded.dispose);
        await reloaded.loadFromStorage();
        expect(reloaded.quietHoursEnabled, isTrue);
        expect(reloaded.quietHoursStartMinutes, 23 * 60);
        expect(reloaded.quietHoursEndMinutes, 6 * 60 + 30);
        expect(reloaded.quietHoursAllowAlarms, isFalse);
        expect(reloaded.quietHoursDeferUntilEnd, isTrue);
      },
    );

    test(
      'ReminderScheduler defers push reminders past quiet hours while preserving allowed alarms and wrapping habit weekdays across midnight',
      () async {
        final notif = _TestNotifSink();
        final alarm = _TestAlarmSink();
        final popup = _TestPopupSink();
        final scheduler = ReminderScheduler(
          notif,
          alarm: alarm,
          email: _TestEmailSink(),
          popup: popup,
        );
        scheduler.updateQuietHours(
          const QuietHoursPolicy(
            enabled: true,
            startMinutes: 22 * 60,
            endMinutes: 7 * 60,
            allowAlarms: true,
            deferUntilEnd: true,
          ),
        );

        final futureDay = DateTime.now().add(const Duration(days: 5));
        final day = DateTime(futureDay.year, futureDay.month, futureDay.day);
        final pushTodo = TodoItem(
          id: 'qh-push',
          title: '夜间待办',
          dueDate: day,
          reminderPlan: ReminderPlan(
            enabled: true,
            rules: [
              ReminderRule(
                id: 'r-push',
                type: ReminderRuleType.absolute,
                kind: ReminderKind.push,
                hour: 23,
                minute: 30,
              ),
            ],
          ),
        );
        final alarmTodo = TodoItem(
          id: 'qh-alarm',
          title: '夜间闹钟',
          dueDate: day,
          reminderPlan: ReminderPlan(
            enabled: true,
            rules: [
              ReminderRule(
                id: 'r-alarm',
                type: ReminderRuleType.absolute,
                kind: ReminderKind.alarm,
                hour: 23,
                minute: 45,
              ),
            ],
          ),
        );
        final habit = Habit(
          id: 'qh-habit',
          name: '睡前复盘',
          reminderPlan: ReminderPlan(
            enabled: true,
            rules: [
              ReminderRule(
                id: 'rh',
                type: ReminderRuleType.weeklyTime,
                kind: ReminderKind.push,
                hour: 23,
                minute: 0,
                weekdays: const [DateTime.monday],
              ),
            ],
          ),
        );

        await scheduler.syncTodos([pushTodo, alarmTodo]);
        await scheduler.syncHabits([habit]);

        final pushScheduled = notif.scheduled.firstWhere(
          (e) => e['payload'] == 'duoyi://todo/qh-push',
        );
        expect(
          pushScheduled['when'],
          DateTime(day.year, day.month, day.day + 1, 7, 0),
        );

        final alarmScheduled = alarm.scheduled.firstWhere(
          (e) => e['payload'] == 'duoyi://todo/qh-alarm?confirm=1',
        );
        expect(
          alarmScheduled['when'],
          DateTime(day.year, day.month, day.day, 23, 45),
        );

        final habitScheduled = popup.scheduled.firstWhere(
          (e) => (e['payload'] as String).contains('qh-habit'),
        );
        expect(habitScheduled['hour'], 7);
        expect(habitScheduled['minute'], 0);
        expect(habitScheduled['weekdays'], const [DateTime.tuesday]);
      },
    );
  });

  group('Contract & Holiday digest invariants', () {
    test(
      'preserves channel IDs, groupKey, iOS categories, background entrypoint, duoyi://focus, and 14-day workday makeup digest',
      () {
        final localIo = File('lib/services/local_notifications_io.dart')
            .readAsStringSync();
        expect(localIo, contains('duoyi_general_alerts_v18'));
        expect(localIo, contains('com.duoyi.duoyi.GROUP_TODO'));
        expect(localIo, contains('com.duoyi.duoyi.GROUP_HABIT'));
        expect(localIo, contains('com.duoyi.duoyi.GROUP_SCHEDULE'));
        expect(localIo, contains('com.duoyi.duoyi.GROUP_FOCUS'));
        expect(localIo, contains('DUOYI_TODO_REMINDER'));
        expect(localIo, contains('DUOYI_HABIT_REMINDER'));
        expect(localIo, contains('DUOYI_ALARM_REMINDER'));
        expect(localIo, contains("@pragma('vm:entry-point')"));
        expect(localIo, contains('duoyiBackgroundNotificationResponse'));

        final notifSrc = File('lib/providers/notification_service.dart')
            .readAsStringSync();
        expect(notifSrc, contains("payload: 'duoyi://focus'"));

        final mainSrc = File('lib/main.dart').readAsStringSync();
        expect(mainSrc, contains('const int _dailyDigestHolidayWindowDays = 14;'));
        expect(mainSrc, contains('HolidayCalendar.isWorkMakeupDay'));
        expect(mainSrc, contains("action == 'toggle_pomodoro'"));
        expect(mainSrc, contains("action == 'stop_pomodoro'"));
        expect(mainSrc, contains("action == 'quick_schedule'"));
        expect(HolidayCalendar.isWorkMakeupDay(DateTime(2026, 2, 15)), isTrue);
      },
    );
  });
}
