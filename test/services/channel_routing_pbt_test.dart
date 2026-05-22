import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:duoyi/models/goal.dart';
import 'package:duoyi/models/habit.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/notification_service.dart';
import 'package:duoyi/services/alarm_service.dart';
import 'package:duoyi/services/notification_permission_exception.dart';
import 'package:duoyi/services/reminder_scheduler.dart';
import 'package:duoyi/services/reminder_sinks.dart';

/// 通道路由属性测试（Task 14.3）。
///
/// Feature: app-alignment-overhaul
/// Property 14 (P14): ∀ `ReminderConfig r`,
///   `r.kind = push  ⟹ 调度最终落到 ReminderNotificationSink.scheduleOnce`
///                     (NotificationService，channel = `duoyi_general_alerts_v7`)；
///   `r.kind = alarm ⟹ 调度最终落到 ReminderAlarmSink.scheduleFullScreen`
///                     (AlarmService，channel = `duoyi_alarm_fullscreen_v6`)。
///
/// Validates: Requirements 4.4, 4.5
///
/// 测试形态：
///   - 使用 `Random(42)` 种子生成 N=50 次"随机但可复现"的迭代；
///   - 每轮构造 1..6 个 TodoItem / GoalItem，随机选 push 或 alarm；
///   - 用 `_RecordingNotificationSink` / `_RecordingAlarmSink` 双 Fake 注入
///     `ReminderScheduler`，观察分发；
///   - 断言：
///       * push 项全部只出现在 Notification 侧，Alarm 侧无相应 id；
///       * alarm 项全部只出现在 Alarm 侧，Notification 侧无相应 id；
///       * 两者的常量 channel id 与设计一致。
void main() {
  /// 固定种子，保证"随机"测试在 CI / 本地完全可复现。
  const int kSeed = 42;

  /// 迭代轮次。
  const int kIterations = 50;

  test('channel id 常量与设计 §2.4 / §3.6 保持一致', () {
    // P14 的其中一半约束是"用对通道 id"：由 NotificationService / AlarmService
    // 的类级常量承载，Scheduler 不重复传递。这里显式断言，防止后续被误改。
    expect(NotificationService.channelId, 'duoyi_general_alerts_v7');
    expect(AlarmService.channelId, 'duoyi_alarm_fullscreen_v6');
  });

  group('P14 - 通道路由（Todo）', () {
    test('push Todo 全部命中 NotificationSink.scheduleOnce；'
        'alarm Todo 全部命中 AlarmSink.scheduleFullScreen', () async {
      final rng = Random(kSeed);
      for (int iter = 0; iter < kIterations; iter++) {
        final notif = _RecordingNotificationSink();
        final alarm = _RecordingAlarmSink();
        final scheduler = ReminderScheduler(notif, alarm: alarm);

        // 1..6 个 todos，每个随机选 push 或 alarm。
        final n = 1 + rng.nextInt(6);
        final pushTodos = <TodoItem>[];
        final alarmTodos = <TodoItem>[];

        final todos = <TodoItem>[];
        for (int i = 0; i < n; i++) {
          final isPush = rng.nextBool();
          final due = _nextHourAligned(
            rng: rng,
            minHoursFromNow: 2,
            maxDaysFromNow: 7,
          );
          final t = TodoItem(
            title: 'iter$iter-todo$i',
            dueDate: due,
            reminder: ReminderConfig(
              enabled: true,
              kind: isPush ? ReminderKind.push : ReminderKind.alarm,
              hour: due.hour,
              minute: due.minute,
            ),
          );
          todos.add(t);
          if (isPush) {
            pushTodos.add(t);
          } else {
            alarmTodos.add(t);
          }
        }

        await scheduler.syncTodos(todos);

        // 每条 push todo 应在 Notification.scheduleOnce 中各出现恰好一次，
        // 且 Alarm 端没有对应 id。
        final pushIntIds = pushTodos.map(_todoRuleIntId).toSet();
        final alarmIntIds = alarmTodos.map(_todoRuleIntId).toSet();

        final notifScheduledIds = notif.scheduleOnceCalls
            .map((c) => c.id)
            .toSet();
        final alarmScheduledIds = alarm.scheduleFullScreenCalls
            .map((c) => c.id)
            .toSet();

        // 精确相等：Scheduler 不应向"另一条通道"外溢。
        expect(
          notifScheduledIds,
          equals(pushIntIds),
          reason:
              'iter=$iter — NotificationSink.scheduleOnce 的 id 集合应 == '
              'push todos 的 id 集合，实际=$notifScheduledIds 期望=$pushIntIds',
        );
        expect(
          alarmScheduledIds,
          equals(alarmIntIds),
          reason:
              'iter=$iter — AlarmSink.scheduleFullScreen 的 id 集合应 == '
              'alarm todos 的 id 集合，实际=$alarmScheduledIds 期望=$alarmIntIds',
        );

        // alarm-kind 不应"回退"走 scheduleDaily 等 push 路径。
        expect(notif.scheduleDailyCalls, isEmpty);
        // 首轮 sync 会主动清理旧版单提醒 id，避免升级后遗留旧调度。
        expect(
          notif.cancelTodoReminderCalls.toSet(),
          equals(todos.map((t) => t.id).toSet()),
        );
        expect(
          alarm.cancelCalls.toSet(),
          containsAll(todos.map((t) => _todoIntId(t.id))),
        );
      }
    });

    test('push ↔ alarm 切换时，旧通道的残留会被清理（双通道 cancel 语义）', () async {
      // 这条不是随机性，而是对 P14 的"切换 kind 时通道不串台"的配套断言，
      // 只跑一次确定性场景即可。
      final notif = _RecordingNotificationSink();
      final alarm = _RecordingAlarmSink();
      final scheduler = ReminderScheduler(notif, alarm: alarm);

      final due = DateTime.now().add(const Duration(hours: 2));
      final t = TodoItem(
        title: 'switching-todo',
        dueDate: due,
        reminder: ReminderConfig(
          enabled: true,
          kind: ReminderKind.push,
          hour: due.hour,
          minute: due.minute,
        ),
      );

      // 1) push 下发
      await scheduler.syncTodos([t]);
      expect(notif.scheduleOnceCalls.length, 1);
      expect(alarm.scheduleFullScreenCalls, isEmpty);

      // 2) 切换为 alarm 并重新 sync
      final t2 = t.copyWith(
        reminder: t.reminder.copyWith(kind: ReminderKind.alarm),
      );
      await scheduler.syncTodos([t2]);

      // 切换后：旧 push 应被 cancel（双通道清理），新 alarm 被下发。
      expect(
        notif.cancelTodoReminderCalls,
        contains(t.id),
        reason: '切换到 alarm 后应调用 notif.cancelTodoReminder 清理旧 push',
      );
      expect(
        alarm.cancelCalls,
        contains(_todoRuleIntId(t)),
        reason: '切换通道时 alarm 侧也会被清（双通道 cancel 语义）',
      );
      expect(alarm.scheduleFullScreenCalls.length, 1);
      expect(alarm.scheduleFullScreenCalls.single.id, _todoRuleIntId(t2));
    });

    test('alarm Todo 的 fullScreen 标志会传到底层闹钟调度', () async {
      final notif = _RecordingNotificationSink();
      final alarm = _RecordingAlarmSink();
      final scheduler = ReminderScheduler(notif, alarm: alarm);

      final due = DateTime.now().add(const Duration(hours: 3));
      final todo = TodoItem(
        title: 'alarm-fullscreen-off',
        dueDate: due,
        reminder: ReminderConfig(
          enabled: true,
          kind: ReminderKind.alarm,
          hour: due.hour,
          minute: due.minute,
          fullScreen: false,
        ),
      );

      await scheduler.syncTodos([todo]);

      expect(alarm.scheduleFullScreenCalls, hasLength(1));
      expect(alarm.scheduleFullScreenCalls.single.fullScreen, isFalse);
    });

    test('alarm Todo 的稍后提醒分钟数会传到底层闹钟调度', () async {
      final notif = _RecordingNotificationSink();
      final alarm = _RecordingAlarmSink();
      final scheduler = ReminderScheduler(notif, alarm: alarm);

      final due = DateTime.now().add(const Duration(hours: 3));
      final todo = TodoItem(
        title: 'alarm-snooze-15',
        dueDate: due,
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'snooze-rule',
              type: ReminderRuleType.absolute,
              kind: ReminderKind.alarm,
              hour: due.hour,
              minute: due.minute,
              snoozeMinutes: 15,
            ),
          ],
        ),
      );

      await scheduler.syncTodos([todo]);

      expect(alarm.scheduleFullScreenCalls, hasLength(1));
      expect(alarm.scheduleFullScreenCalls.single.snoozeMinutes, 15);
    });

    test('alarm Todo 的震动开关会传到底层闹钟调度', () async {
      final notif = _RecordingNotificationSink();
      final alarm = _RecordingAlarmSink();
      final scheduler = ReminderScheduler(notif, alarm: alarm);

      final due = DateTime.now().add(const Duration(hours: 3));
      final todo = TodoItem(
        title: 'alarm-vibrate-off',
        dueDate: due,
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'vibrate-off',
              type: ReminderRuleType.absolute,
              kind: ReminderKind.alarm,
              hour: due.hour,
              minute: due.minute,
              vibrate: false,
            ),
          ],
        ),
      );

      await scheduler.syncTodos([todo]);

      expect(alarm.scheduleFullScreenCalls, hasLength(1));
      expect(alarm.scheduleFullScreenCalls.single.vibrate, isFalse);
    });

    test('alarm Todo 的重复提醒次数会传到底层闹钟调度', () async {
      final notif = _RecordingNotificationSink();
      final alarm = _RecordingAlarmSink();
      final scheduler = ReminderScheduler(notif, alarm: alarm);

      final due = DateTime.now().add(const Duration(hours: 3));
      final todo = TodoItem(
        title: 'alarm-repeat-2',
        dueDate: due,
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'repeat-rule',
              type: ReminderRuleType.absolute,
              kind: ReminderKind.alarm,
              hour: due.hour,
              minute: due.minute,
              snoozeMinutes: 10,
              repeatCount: 2,
            ),
          ],
        ),
      );

      await scheduler.syncTodos([todo]);

      expect(alarm.scheduleFullScreenCalls, hasLength(1));
      expect(alarm.scheduleFullScreenCalls.single.repeatCount, 2);
    });

    test('每日 alarm Todo 的重复提醒次数会传到底层闹钟调度', () async {
      final notif = _RecordingNotificationSink();
      final alarm = _RecordingAlarmSink();
      final scheduler = ReminderScheduler(notif, alarm: alarm);

      final todo = TodoItem(
        title: 'daily-repeat-3',
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'daily-repeat',
              type: ReminderRuleType.dailyTime,
              kind: ReminderKind.alarm,
              hour: 9,
              minute: 20,
              snoozeMinutes: 5,
              repeatCount: 3,
            ),
          ],
        ),
      );

      await scheduler.syncTodos([todo]);

      expect(alarm.scheduleDailyFullScreenCalls, hasLength(1));
      expect(alarm.scheduleDailyFullScreenCalls.single.repeatCount, 3);
    });

    test('一个 Todo 的多条 rule 会分别下发、删除后按 rule id 清理', () async {
      final notif = _RecordingNotificationSink();
      final alarm = _RecordingAlarmSink();
      final scheduler = ReminderScheduler(notif, alarm: alarm);

      final due = DateTime.now().add(const Duration(days: 2));
      final plan = ReminderPlan(
        enabled: true,
        rules: [
          ReminderRule(
            id: 'due',
            type: ReminderRuleType.absolute,
            kind: ReminderKind.push,
            hour: due.hour,
            minute: due.minute,
          ),
          ReminderRule(
            id: 'daily',
            type: ReminderRuleType.dailyTime,
            kind: ReminderKind.push,
            hour: 8,
            minute: 15,
          ),
          ReminderRule(
            id: 'weekly',
            type: ReminderRuleType.weeklyTime,
            kind: ReminderKind.alarm,
            hour: 21,
            minute: 0,
            weekdays: const [1, 3, 5],
          ),
        ],
      );
      final todo = TodoItem(
        id: 'multi-todo',
        title: '多提醒任务',
        dueDate: due,
        reminderPlan: plan,
      );

      await scheduler.syncTodos([todo]);

      expect(
        notif.scheduleOnceCalls.map((c) => c.id),
        contains(_ruleIntId('todo', todo.id, 'due')),
      );
      expect(notif.scheduleOnceCalls.single.payload, 'duoyi://todo/${todo.id}');
      expect(
        notif.scheduleDailyCalls.map((c) => c.id),
        contains(_ruleIntId('todo', todo.id, 'daily')),
      );
      expect(
        alarm.scheduleDailyFullScreenCalls.map((c) => c.id),
        contains(_ruleIntId('todo', todo.id, 'weekly')),
      );
      expect(
        alarm.scheduleDailyFullScreenCalls.single.weekdays,
        equals(const [1, 3, 5]),
      );

      final updated = todo.copyWith(
        reminderPlan: plan.copyWith(rules: plan.rules.take(2).toList()),
      );
      await scheduler.syncTodos([updated]);

      expect(
        notif.cancelCalls,
        contains(_ruleIntId('todo', todo.id, 'weekly')),
      );
      expect(
        alarm.cancelCalls,
        contains(_ruleIntId('todo', todo.id, 'weekly')),
      );
    });

    test('单条 rule 调度失败不会阻断同一轮其它提醒', () async {
      final notif = _RecordingNotificationSink();
      final alarm = _RecordingAlarmSink();
      final scheduler = ReminderScheduler(notif, alarm: alarm);
      final due = DateTime.now().add(const Duration(days: 2));
      final todo = TodoItem(
        id: 'partial-failure',
        title: '失败隔离',
        dueDate: due,
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'broken',
              type: ReminderRuleType.absolute,
              kind: ReminderKind.push,
              hour: due.hour,
              minute: due.minute,
            ),
            ReminderRule(
              id: 'ok',
              type: ReminderRuleType.dailyTime,
              kind: ReminderKind.push,
              hour: 9,
              minute: 0,
            ),
          ],
        ),
      );
      notif.failScheduleOnceIds.add(_ruleIntId('todo', todo.id, 'broken'));

      await scheduler.syncTodos([todo]);

      expect(notif.scheduleOnceCalls, isEmpty);
      expect(
        notif.scheduleDailyCalls.map((c) => c.id),
        contains(_ruleIntId('todo', todo.id, 'ok')),
      );
    });

    test('alarm 权限失败时回退到 push，避免提醒直接丢失', () async {
      final notif = _RecordingNotificationSink();
      final alarm = _RecordingAlarmSink();
      final scheduler = ReminderScheduler(notif, alarm: alarm);

      final due = DateTime.now().add(const Duration(hours: 2));
      final todo = TodoItem(
        id: 'alarm-fallback',
        title: '闹钟权限失败回退',
        dueDate: due,
        reminder: ReminderConfig(
          enabled: true,
          kind: ReminderKind.alarm,
          hour: due.hour,
          minute: due.minute,
        ),
      );
      alarm.failFullScreenIds.add(_todoRuleIntId(todo));

      await scheduler.syncTodos([todo]);

      expect(
        notif.scheduleOnceCalls.map((c) => c.id),
        contains(_todoRuleIntId(todo)),
      );
      expect(notif.scheduleOnceCalls.single.payload, 'duoyi://todo/${todo.id}');
    });

    test('通知权限失败时不会抛出未处理异常，也不会记录为已调度', () async {
      final notif = _RecordingNotificationSink()
        ..denyScheduleOnce = true
        ..denyScheduleDaily = true;
      final alarm = _RecordingAlarmSink();
      final scheduler = ReminderScheduler(notif, alarm: alarm);

      final due = DateTime.now().add(const Duration(days: 2));
      final todo = TodoItem(
        id: 'permission-denied',
        title: '通知权限失败',
        dueDate: due,
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'once',
              type: ReminderRuleType.absolute,
              kind: ReminderKind.push,
              hour: due.hour,
              minute: due.minute,
            ),
            ReminderRule(
              id: 'daily',
              type: ReminderRuleType.dailyTime,
              kind: ReminderKind.push,
              hour: 9,
              minute: 0,
            ),
          ],
        ),
      );

      await scheduler.syncTodos([todo]);

      expect(notif.scheduleOnceCalls, isEmpty);
      expect(notif.scheduleDailyCalls, isEmpty);

      notif
        ..denyScheduleOnce = false
        ..denyScheduleDaily = false;
      await scheduler.syncTodos([todo]);

      expect(
        notif.scheduleOnceCalls.map((c) => c.id),
        contains(_ruleIntId('todo', todo.id, 'once')),
      );
      expect(
        notif.scheduleDailyCalls.map((c) => c.id),
        contains(_ruleIntId('todo', todo.id, 'daily')),
      );
    });
  });

  group('P14 - 通道路由（Goal）', () {
    test('push Goal / alarm Goal 分发到对应 sink，且互不串扰', () async {
      final rng = Random(kSeed);
      for (int iter = 0; iter < kIterations; iter++) {
        final notif = _RecordingNotificationSink();
        final alarm = _RecordingAlarmSink();
        final scheduler = ReminderScheduler(notif, alarm: alarm);

        final n = 1 + rng.nextInt(6);
        final pushGoals = <GoalItem>[];
        final alarmGoals = <GoalItem>[];

        final goals = <GoalItem>[];
        for (int i = 0; i < n; i++) {
          final isPush = rng.nextBool();
          // 用"今天稍后 1..23 小时"的 H/M，保证 `_resolveGoal` 能算出
          // 一个将来的 when（若已过则自动推到次日）。
          final hour = rng.nextInt(24);
          final minute = rng.nextInt(60);
          final g = GoalItem(
            title: 'iter$iter-goal$i',
            startDate: DateTime.now().subtract(const Duration(days: 1)),
            reminder: ReminderConfig(
              enabled: true,
              kind: isPush ? ReminderKind.push : ReminderKind.alarm,
              hour: hour,
              minute: minute,
            ),
          );
          goals.add(g);
          if (isPush) {
            pushGoals.add(g);
          } else {
            alarmGoals.add(g);
          }
        }

        await scheduler.syncGoals(goals);

        final pushIntIds = pushGoals.map(_goalRuleIntId).toSet();
        final alarmIntIds = alarmGoals.map(_goalRuleIntId).toSet();

        final notifScheduledIds = notif.scheduleOnceCalls
            .map((c) => c.id)
            .toSet();
        final alarmScheduledIds = alarm.scheduleFullScreenCalls
            .map((c) => c.id)
            .toSet();

        expect(
          notifScheduledIds,
          equals(pushIntIds),
          reason:
              'iter=$iter — Goal push 的 id 集合应与 Notification.scheduleOnce 精确一致',
        );
        expect(
          alarmScheduledIds,
          equals(alarmIntIds),
          reason:
              'iter=$iter — Goal alarm 的 id 集合应与 Alarm.scheduleFullScreen 精确一致',
        );
        for (final call in notif.scheduleOnceCalls) {
          expect(call.payload, startsWith('duoyi://goal/'));
        }
      }
    });
  });

  group('P14 - Habit 路径走强提醒', () {
    test('syncHabits 下发全屏闹钟并携带确认打卡 payload', () async {
      final notif = _RecordingNotificationSink();
      final alarm = _RecordingAlarmSink();
      final scheduler = ReminderScheduler(notif, alarm: alarm);
      final habit = Habit(
        id: 'habit-alarm',
        name: '喝水',
        remind: true,
        remindHour: 8,
        remindMinute: 30,
        activeWeekdays: const [0, 2, 4],
      );

      await scheduler.syncHabits([habit]);

      expect(notif.scheduleHabitReminderCalls, isEmpty);
      expect(alarm.scheduleDailyFullScreenCalls, hasLength(1));
      final call = alarm.scheduleDailyFullScreenCalls.single;
      expect(call.id, _idFor('habit_${habit.id}'));
      expect(call.title, contains('习惯打卡'));
      expect(call.body, contains(habit.name));
      expect(call.hour, 8);
      expect(call.minute, 30);
      expect(call.weekdays, [1, 3, 5]);
      expect(call.payload, 'duoyi://habit/${habit.id}?confirm=1');
      expect(call.fullScreen, isTrue);
    });

    test('alarm 权限失败时回退到 push，避免习惯提醒丢失', () async {
      final notif = _RecordingNotificationSink();
      final alarm = _RecordingAlarmSink();
      final scheduler = ReminderScheduler(notif, alarm: alarm);
      final habit = Habit(
        id: 'habit-fallback',
        name: '晨练',
        remind: true,
        remindHour: 7,
        remindMinute: 15,
      );
      alarm.failDailyFullScreenIds.add(_idFor('habit_${habit.id}'));

      await scheduler.syncHabits([habit]);

      expect(alarm.scheduleDailyFullScreenCalls, isEmpty);
      expect(notif.scheduleHabitReminderCalls, [habit.id]);
    });
  });
}

// ---------------------------------------------------------------------------
// 工具：id 映射（与 ReminderScheduler._idFor 等价的稳定 hash）。
// 这里复制而非反射，是因为 _idFor 是私有方法；保持与实现同步即可。
// ---------------------------------------------------------------------------

int _idFor(String key) {
  int h = 0;
  for (final c in key.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return h;
}

int _todoIntId(String todoId) => _idFor('todo_$todoId');
int _ruleIntId(String objectType, String objectId, String ruleId) =>
    _idFor('$objectType:$objectId:$ruleId');
int _todoRuleIntId(TodoItem todo) =>
    _ruleIntId('todo', todo.id, todo.reminderPlan.primaryRule!.id);
int _goalRuleIntId(GoalItem goal) =>
    _ruleIntId('goal', goal.id, goal.reminderPlan.primaryRule!.id);

/// 生成一个从现在起至少 [minHoursFromNow] 小时、至多 [maxDaysFromNow] 天后的
/// 随机时间，且小时/分钟均在合法范围内，便于 Todo 的 reminder 能命中
/// `_resolveTodo` 的"未过期"分支。
DateTime _nextHourAligned({
  required Random rng,
  required int minHoursFromNow,
  required int maxDaysFromNow,
}) {
  final now = DateTime.now();
  final hours = minHoursFromNow + rng.nextInt(maxDaysFromNow * 24);
  final candidate = now.add(Duration(hours: hours));
  // 对齐到 (hour, minute)（秒取 0，避免 Scheduler.reminderAt 回写时出现毫秒抖动）。
  return DateTime(
    candidate.year,
    candidate.month,
    candidate.day,
    candidate.hour,
    rng.nextInt(60),
  );
}

// ---------------------------------------------------------------------------
// Fakes：Recording sinks
// ---------------------------------------------------------------------------

class _ScheduleOnceCall {
  final int id;
  final String title;
  final String body;
  final DateTime when;
  final String? payload;
  const _ScheduleOnceCall({
    required this.id,
    required this.title,
    required this.body,
    required this.when,
    required this.payload,
  });
}

class _ScheduleDailyCall {
  final int id;
  final int hour;
  final int minute;
  final List<int>? weekdays;
  const _ScheduleDailyCall({
    required this.id,
    required this.hour,
    required this.minute,
    required this.weekdays,
  });
}

class _ScheduleFullScreenCall {
  final int id;
  final String title;
  final String body;
  final DateTime when;
  final String? payload;
  final bool requireExactAlarm;
  final bool fullScreen;
  final bool vibrate;
  final int snoozeMinutes;
  final int repeatCount;
  const _ScheduleFullScreenCall({
    required this.id,
    required this.title,
    required this.body,
    required this.when,
    required this.payload,
    required this.requireExactAlarm,
    required this.fullScreen,
    required this.vibrate,
    required this.snoozeMinutes,
    required this.repeatCount,
  });
}

class _ScheduleDailyFullScreenCall {
  final int id;
  final String title;
  final String body;
  final int hour;
  final int minute;
  final List<int>? weekdays;
  final String? payload;
  final bool fullScreen;
  final bool vibrate;
  final int snoozeMinutes;
  final int repeatCount;

  const _ScheduleDailyFullScreenCall({
    required this.id,
    required this.title,
    required this.body,
    required this.hour,
    required this.minute,
    required this.weekdays,
    required this.payload,
    required this.fullScreen,
    required this.vibrate,
    required this.snoozeMinutes,
    required this.repeatCount,
  });
}

class _RecordingNotificationSink implements ReminderNotificationSink {
  final List<_ScheduleOnceCall> scheduleOnceCalls = [];
  final List<_ScheduleDailyCall> scheduleDailyCalls = [];
  final List<int> cancelCalls = [];
  final List<String> cancelTodoReminderCalls = [];
  final List<String> cancelHabitReminderCalls = [];
  final List<String> cancelAnniversaryCalls = [];
  final List<String> scheduleHabitReminderCalls = [];
  final List<String> scheduleAnniversaryCalls = [];
  final Set<int> failScheduleOnceIds = {};
  bool denyScheduleOnce = false;
  bool denyScheduleDaily = false;

  @override
  Future<void> scheduleOnce({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
  }) async {
    if (denyScheduleOnce) {
      throw const NotificationPermissionDeniedException();
    }
    if (failScheduleOnceIds.remove(id)) {
      throw StateError('forced scheduleOnce failure: $id');
    }
    scheduleOnceCalls.add(
      _ScheduleOnceCall(
        id: id,
        title: title,
        body: body,
        when: when,
        payload: payload,
      ),
    );
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
    scheduleDailyCalls.add(
      _ScheduleDailyCall(
        id: id,
        hour: hour,
        minute: minute,
        weekdays: weekdays,
      ),
    );
  }

  @override
  Future<void> cancel(int id) async {
    cancelCalls.add(id);
  }

  @override
  Future<void> cancelTodoReminder(String todoId) async {
    cancelTodoReminderCalls.add(todoId);
  }

  @override
  Future<void> cancelHabitReminder(String habitId) async {
    cancelHabitReminderCalls.add(habitId);
  }

  @override
  Future<void> cancelAnniversary(String annId) async {
    cancelAnniversaryCalls.add(annId);
  }

  @override
  Future<void> scheduleHabitReminder({
    required String habitId,
    required String habitName,
    required int hour,
    required int minute,
    List<int>? weekdays,
  }) async {
    scheduleHabitReminderCalls.add(habitId);
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
    scheduleAnniversaryCalls.add(annId);
  }
}

class _RecordingAlarmSink implements ReminderAlarmSink {
  final List<_ScheduleFullScreenCall> scheduleFullScreenCalls = [];
  final List<_ScheduleDailyFullScreenCall> scheduleDailyFullScreenCalls = [];
  final List<int> cancelCalls = [];
  final Set<int> failFullScreenIds = {};
  final Set<int> failDailyFullScreenIds = {};

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
    if (failFullScreenIds.remove(id)) {
      throw const AlarmPermissionDeniedException('forced alarm failure');
    }
    scheduleFullScreenCalls.add(
      _ScheduleFullScreenCall(
        id: id,
        title: title,
        body: body,
        when: when,
        payload: payload,
        requireExactAlarm: requireExactAlarm,
        fullScreen: fullScreen,
        vibrate: vibrate,
        snoozeMinutes: snoozeMinutes,
        repeatCount: repeatCount,
      ),
    );
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
    if (failDailyFullScreenIds.remove(id)) {
      throw const AlarmPermissionDeniedException('forced daily alarm failure');
    }
    scheduleDailyFullScreenCalls.add(
      _ScheduleDailyFullScreenCall(
        id: id,
        title: title,
        body: body,
        hour: hour,
        minute: minute,
        weekdays: weekdays,
        payload: payload,
        fullScreen: fullScreen,
        vibrate: vibrate,
        snoozeMinutes: snoozeMinutes,
        repeatCount: repeatCount,
      ),
    );
  }

  @override
  Future<void> cancel(int id) async {
    cancelCalls.add(id);
  }
}
