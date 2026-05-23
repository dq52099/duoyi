import 'package:flutter/foundation.dart';

import '../models/anniversary.dart';
import '../models/countdown.dart';
import '../models/goal.dart';
import '../models/habit.dart';
import '../models/todo.dart';
import 'alarm_service.dart';
import 'notification_permission_exception.dart';
import 'reminder_sinks.dart';

/// 推送 / 闹钟路由分发用的统一载荷。
class _DispatchPayload {
  final int id;
  final String title;
  final String body;
  final DateTime when;
  final String? payload;
  final bool fullScreen;
  final bool vibrate;
  final int snoozeMinutes;
  final int repeatCount;

  const _DispatchPayload({
    required this.id,
    required this.title,
    required this.body,
    required this.when,
    this.payload,
    this.fullScreen = true,
    this.vibrate = true,
    this.snoozeMinutes = 0,
    this.repeatCount = 0,
  });
}

class _ScheduledRule {
  final ReminderKind kind;
  final _DispatchMode mode;
  final String scope;

  const _ScheduledRule({
    required this.kind,
    required this.mode,
    required this.scope,
  });
}

enum _DispatchMode { once, repeating }

class _ResolvedRule {
  final String objectType;
  final String objectId;
  final String ruleId;
  final ReminderKind kind;
  final _DispatchMode mode;
  final ReminderRuleType ruleType;
  final String title;
  final String body;
  final String payload;
  final bool fullScreen;
  final bool vibrate;
  final int snoozeMinutes;
  final int repeatCount;
  final DateTime? when;
  final int? hour;
  final int? minute;
  final List<int> weekdays;
  final String scope;

  const _ResolvedRule({
    required this.objectType,
    required this.objectId,
    required this.ruleId,
    required this.kind,
    required this.mode,
    required this.ruleType,
    required this.title,
    required this.body,
    required this.payload,
    required this.fullScreen,
    required this.vibrate,
    required this.snoozeMinutes,
    required this.repeatCount,
    required this.scope,
    this.when,
    this.hour,
    this.minute,
    this.weekdays = const <int>[],
  });

  String get key => '$objectType:$objectId:$ruleId';
}

/// 根据 todo / habit / anniversary / goal 数据幂等地同步本地通知 / 闹钟队列。
///
/// 每次数据变化时由 `main.dart` 调用对应的 `syncXxx` 或 [resyncAll]。服务
/// 内部保证：
/// 1. 先取消自己管理过的 id（同时清理 push 与 alarm 两条通道，防止 `kind`
///    由 `push` 翻转到 `alarm` 时出现遗留调度）；
/// 2. 再按最新数据通过 [_dispatch] 路由到 `NotificationService`（push）或
///    `AlarmService`（alarm）重新下发。
///
/// R4.1 / R4.4 / R4.5 / R4.7 / R4.8：本类是协调器，职责严格与
/// `NotificationService` 和 `AlarmService` 分离；两者互不直接通话。
class ReminderScheduler {
  final ReminderNotificationSink notif;
  final ReminderAlarmSink alarm;
  final ReminderEmailSink email;

  /// 上一轮已下发的 todo / goal rule → 通道与调度形态。
  final Map<String, Map<String, _ScheduledRule>> _scheduledTodoRules = {};
  final Map<String, Map<String, _ScheduledRule>> _scheduledGoalRules = {};
  final Set<String> _scheduledHabitIds = {};
  final Set<String> _scheduledAnniIds = {};
  final Map<String, String> _scheduledCountdownScopes = {};

  /// [notif] 必传；[alarm] 默认取 `AlarmService.instance` 单例，便于测试时
  /// 注入 fake。[email] 默认 no-op，未配置邮件服务时不会误发本地通知。
  /// 三者均以 sink 接口表达，便于属性测试用 Fake 实例注入。
  ReminderScheduler(
    this.notif, {
    ReminderAlarmSink? alarm,
    ReminderEmailSink? email,
  }) : alarm = alarm ?? AlarmService.instance,
       email = email ?? const NoopReminderEmailSink();

  // -------------------------------------------------------------------------
  // 公共 API
  // -------------------------------------------------------------------------

  /// 按最新的 [todos] 幂等地重新同步待办提醒。
  Future<void> syncTodos(Iterable<TodoItem> todos) async {
    final wanted = <String, Map<String, _ResolvedRule>>{};
    for (final t in todos) {
      if (t.isCompleted) continue;
      final resolved = _resolveTodoRules(t);
      if (resolved.isEmpty) continue;
      wanted[t.id] = {for (final rule in resolved) rule.ruleId: rule};
    }
    await _syncRuleObjects(
      objectType: 'todo',
      wanted: wanted,
      scheduled: _scheduledTodoRules,
      cancelLegacy: _cancelTodoLegacy,
    );
  }

  /// 按最新的 [habits] 幂等地重新同步习惯提醒。
  ///
  /// 习惯提醒默认走普通通知通道，payload 进入确认打卡弹窗。强提醒只保留
  /// 给用户在提醒规则里明确选择的 `alarm` 场景，避免默认响铃/弹屏吓人。
  Future<void> syncHabits(Iterable<Habit> habits) async {
    final wanted = <String, Habit>{};
    for (final h in habits) {
      if (!h.remind) continue;
      if (h.remindHour == null || h.remindMinute == null) continue;
      wanted[h.id] = h;
    }
    for (final id in _scheduledHabitIds.toList()) {
      await notif.cancelHabitReminder(id);
      await alarm.cancel(_idFor('habit_$id'));
    }
    for (final h in wanted.values) {
      // activeWeekdays 是 0..6(周一=0)，转换到 flutter_local_notifications 的
      // 1..7(周一=1..周日=7)
      final weekdays = h.activeWeekdays.map((w) => w + 1).toList();
      try {
        await notif.scheduleHabitReminder(
          habitId: h.id,
          habitName: h.name,
          hour: h.remindHour!,
          minute: h.remindMinute!,
          weekdays: weekdays.isEmpty ? null : weekdays,
        );
      } on NotificationPermissionDeniedException catch (e) {
        debugPrint(
          '[ReminderScheduler] habit notification permission denied for ${h.id}: $e',
        );
      } catch (e, st) {
        debugPrint(
          '[ReminderScheduler] habit notification dispatch failed for ${h.id}: $e\n$st',
        );
      }
    }
    _scheduledHabitIds
      ..clear()
      ..addAll(wanted.keys);
  }

  /// 按最新的纪念日 [items] 幂等地重新同步提醒。
  ///
  /// 纪念日 `reminderKind` 为 `alarm` 时走全屏闹钟通道；精准闹钟权限不足
  /// 时自动降级为 push。
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
      await alarm.cancel(_idFor('anni_alarm_$id'));
    }
    for (final a in wanted.values) {
      final remindAt = DateTime(
        a.nextOccurrence.year,
        a.nextOccurrence.month,
        a.nextOccurrence.day,
        a.remindHour,
        a.remindMinute,
      ).subtract(Duration(days: a.remindDaysBefore));
      if (!remindAt.isAfter(DateTime.now())) {
        continue;
      }

      if (a.reminderKind == ReminderKind.alarm) {
        try {
          await alarm.scheduleFullScreen(
            id: _idFor('anni_alarm_${a.id}'),
            title: '⏰ 纪念日提醒',
            body: a.remindDaysBefore == 0
                ? '今天是 ${a.title}'
                : '${a.remindDaysBefore} 天后是 ${a.title}',
            when: remindAt,
            payload: 'duoyi://anniversary/${a.id}',
          );
        } on AlarmPermissionDeniedException catch (e) {
          debugPrint(
            '[ReminderScheduler] anniversary alarm permission denied for ${a.id}: $e',
          );
          await notif.scheduleAnniversary(
            annId: a.id,
            title: a.title,
            whenDate: a.nextOccurrence,
            daysBefore: a.remindDaysBefore,
            hour: a.remindHour,
            minute: a.remindMinute,
          );
        } on NotificationPermissionDeniedException catch (e) {
          debugPrint(
            '[ReminderScheduler] anniversary notification permission denied for ${a.id}: $e',
          );
        } catch (e, st) {
          debugPrint(
            '[ReminderScheduler] anniversary alarm dispatch failed for ${a.id}: $e\n$st',
          );
          await notif.scheduleAnniversary(
            annId: a.id,
            title: a.title,
            whenDate: a.nextOccurrence,
            daysBefore: a.remindDaysBefore,
            hour: a.remindHour,
            minute: a.remindMinute,
          );
        }
      } else {
        try {
          await notif.scheduleAnniversary(
            annId: a.id,
            title: a.title,
            whenDate: a.nextOccurrence,
            daysBefore: a.remindDaysBefore,
            hour: a.remindHour,
            minute: a.remindMinute,
          );
        } on NotificationPermissionDeniedException catch (e) {
          debugPrint(
            '[ReminderScheduler] anniversary push permission denied for ${a.id}: $e',
          );
        }
      }
    }
    _scheduledAnniIds
      ..clear()
      ..addAll(wanted.keys);
  }

  /// 按最新的倒数日 [items] 幂等地同步到期提醒。
  Future<void> syncCountdowns(Iterable<CountdownItem> items) async {
    final now = DateTime.now();
    final wanted = <String, CountdownItem>{};
    final scopes = <String, String>{};
    for (final item in items) {
      if (!item.remind) continue;
      final when = _countdownReminderAt(item);
      if (!when.isAfter(now)) continue;
      wanted[item.id] = item;
      scopes[item.id] = _countdownScope(item, when);
    }

    for (final id in _scheduledCountdownScopes.keys.toList()) {
      final nextScope = scopes[id];
      if (nextScope == null || _scheduledCountdownScopes[id] != nextScope) {
        await _cancelCountdown(id);
        _scheduledCountdownScopes.remove(id);
      }
    }

    for (final item in wanted.values) {
      final scope = scopes[item.id]!;
      if (_scheduledCountdownScopes[item.id] == scope) continue;
      try {
        await notif.scheduleOnce(
          id: _idFor('countdown:${item.id}:due'),
          title: '🔔 倒数日提醒',
          body:
              '${item.title} · ${item.daysRemaining >= 0 ? '还有 ${item.daysRemaining} 天' : '已过 ${-item.daysRemaining} 天'}',
          when: _countdownReminderAt(item),
          payload: 'duoyi://countdown/${item.id}',
        );
        _scheduledCountdownScopes[item.id] = scope;
      } on NotificationPermissionDeniedException catch (e) {
        debugPrint(
          '[ReminderScheduler] countdown notification permission denied for ${item.id}: $e',
        );
      }
    }
  }

  /// 按最新的 [goals] 幂等地重新同步目标提醒（支持多 rule）。
  Future<void> syncGoals(Iterable<GoalItem> goals) async {
    final wanted = <String, Map<String, _ResolvedRule>>{};
    for (final g in goals) {
      if (g.status != GoalStatus.active) continue;
      final resolved = _resolveGoalRules(g);
      if (resolved.isEmpty) continue;
      wanted[g.id] = {for (final rule in resolved) rule.ruleId: rule};
    }
    await _syncRuleObjects(
      objectType: 'goal',
      wanted: wanted,
      scheduled: _scheduledGoalRules,
      cancelLegacy: _cancelGoalLegacy,
    );
  }

  /// 时区变化、权限变化、应用冷启动时整轮重放（R4.7）。
  Future<void> resyncAll({
    required Iterable<TodoItem> todos,
    required Iterable<Habit> habits,
    required Iterable<Anniversary> annis,
    required Iterable<GoalItem> goals,
    Iterable<CountdownItem> countdowns = const <CountdownItem>[],
  }) async {
    for (final id in _scheduledTodoRules.keys.toList()) {
      await _cancelRuleObjects('todo', id, _scheduledTodoRules[id]!.keys);
      await _cancelTodoLegacy(id);
    }
    for (final id in _scheduledGoalRules.keys.toList()) {
      await _cancelRuleObjects('goal', id, _scheduledGoalRules[id]!.keys);
      await _cancelGoalLegacy(id);
    }
    for (final id in _scheduledHabitIds.toList()) {
      await notif.cancelHabitReminder(id);
      await alarm.cancel(_idFor('habit_$id'));
    }
    for (final id in _scheduledAnniIds.toList()) {
      await notif.cancelAnniversary(id);
    }
    for (final id in _scheduledCountdownScopes.keys.toList()) {
      await _cancelCountdown(id);
    }
    _scheduledTodoRules.clear();
    _scheduledGoalRules.clear();
    _scheduledHabitIds.clear();
    _scheduledAnniIds.clear();
    _scheduledCountdownScopes.clear();

    await syncTodos(todos);
    await syncHabits(habits);
    await syncAnniversaries(annis);
    await syncGoals(goals);
    await syncCountdowns(countdowns);
  }

  // -------------------------------------------------------------------------
  // 内部：通道路由
  // -------------------------------------------------------------------------

  /// 按 [kind] 路由到 push、alarm 或 email。权限不足时记录并返回 false，
  /// 避免 ChangeNotifier 监听回调里出现未处理异步异常。
  Future<bool> _dispatch({
    required ReminderKind kind,
    required _DispatchPayload payload,
  }) async {
    switch (kind) {
      case ReminderKind.push:
        try {
          await notif.scheduleOnce(
            id: payload.id,
            title: payload.title,
            body: payload.body,
            when: payload.when,
            payload: payload.payload,
          );
          return true;
        } on NotificationPermissionDeniedException catch (e) {
          debugPrint(
            '[ReminderScheduler] push notification permission denied for ${payload.id}: $e',
          );
          return false;
        }
      case ReminderKind.alarm:
        try {
          await alarm.scheduleFullScreen(
            id: payload.id,
            title: payload.title,
            body: payload.body,
            when: payload.when,
            payload: payload.payload,
            fullScreen: payload.fullScreen,
            vibrate: payload.vibrate,
            snoozeMinutes: payload.snoozeMinutes,
            repeatCount: payload.repeatCount,
          );
          return true;
        } on AlarmPermissionDeniedException catch (e) {
          debugPrint(
            '[ReminderScheduler] alarm permission denied for ${payload.id}: $e',
          );
          try {
            await notif.scheduleOnce(
              id: payload.id,
              title: payload.title,
              body: payload.body,
              when: payload.when,
              payload: _fallbackPayload(payload.payload),
            );
            return true;
          } on NotificationPermissionDeniedException catch (fallbackError) {
            debugPrint(
              '[ReminderScheduler] alarm fallback notification permission denied for ${payload.id}: $fallbackError',
            );
            return false;
          }
        } on NotificationPermissionDeniedException catch (e) {
          debugPrint(
            '[ReminderScheduler] alarm notification permission denied for ${payload.id}: $e',
          );
          return false;
        }
      case ReminderKind.email:
        await email.scheduleOnce(
          id: payload.id,
          title: payload.title,
          body: payload.body,
          when: payload.when,
          payload: payload.payload,
        );
        return true;
    }
  }

  Future<bool> _dispatchRepeating(_ResolvedRule rule) async {
    switch (rule.kind) {
      case ReminderKind.push:
        try {
          await notif.scheduleDaily(
            id: _idFor(rule.key),
            title: rule.title,
            body: rule.body,
            hour: rule.hour!,
            minute: rule.minute!,
            weekdays: rule.weekdays.isEmpty ? null : rule.weekdays,
            payload: rule.payload,
          );
          return true;
        } on NotificationPermissionDeniedException catch (e) {
          debugPrint(
            '[ReminderScheduler] repeating push permission denied for ${rule.key}: $e',
          );
          return false;
        }
      case ReminderKind.alarm:
        try {
          await alarm.scheduleDailyFullScreen(
            id: _idFor(rule.key),
            title: rule.title,
            body: rule.body,
            hour: rule.hour!,
            minute: rule.minute!,
            weekdays: rule.weekdays.isEmpty ? null : rule.weekdays,
            payload: rule.payload,
            fullScreen: rule.fullScreen,
            vibrate: rule.vibrate,
            snoozeMinutes: rule.snoozeMinutes,
            repeatCount: rule.repeatCount,
          );
          return true;
        } on AlarmPermissionDeniedException catch (e) {
          debugPrint(
            '[ReminderScheduler] alarm permission denied for ${rule.key}: $e',
          );
          try {
            await notif.scheduleDaily(
              id: _idFor(rule.key),
              title: rule.title,
              body: rule.body,
              hour: rule.hour!,
              minute: rule.minute!,
              weekdays: rule.weekdays.isEmpty ? null : rule.weekdays,
              payload: _fallbackPayload(rule.payload),
            );
            return true;
          } on NotificationPermissionDeniedException catch (fallbackError) {
            debugPrint(
              '[ReminderScheduler] repeating alarm fallback permission denied for ${rule.key}: $fallbackError',
            );
            return false;
          }
        } on NotificationPermissionDeniedException catch (e) {
          debugPrint(
            '[ReminderScheduler] alarm notification permission denied for ${rule.key}: $e',
          );
          return false;
        }
      case ReminderKind.email:
        await email.scheduleRepeating(
          id: _idFor(rule.key),
          title: rule.title,
          body: rule.body,
          hour: rule.hour!,
          minute: rule.minute!,
          weekdays: rule.weekdays.isEmpty ? null : rule.weekdays,
          payload: rule.payload,
        );
        return true;
    }
  }

  // -------------------------------------------------------------------------
  // 内部：取消
  // -------------------------------------------------------------------------

  Future<void> _cancelTodo(String todoId) async {
    // 双通道清理：即便本地记录的是 push，用户从 alarm 切过来时也能扫到尾巴。
    await notif.cancelTodoReminder(todoId);
    await alarm.cancel(_idFor('todo_$todoId'));
  }

  Future<void> _cancelGoal(String goalId) async {
    final id = _idFor('goal_$goalId');
    await notif.cancel(id);
    await alarm.cancel(id);
  }

  Future<void> _cancelTodoLegacy(String todoId) => _cancelTodo(todoId);

  Future<void> _cancelGoalLegacy(String goalId) => _cancelGoal(goalId);

  Future<void> _cancelCountdown(String countdownId) async {
    final id = _idFor('countdown:$countdownId:due');
    await notif.cancel(id);
    await alarm.cancel(id);
  }

  Future<void> _cancelRuleObjects(
    String objectType,
    String objectId,
    Iterable<String> ruleIds,
  ) async {
    for (final ruleId in ruleIds) {
      await _cancelRule(objectType, objectId, ruleId);
    }
  }

  Future<void> _cancelRule(
    String objectType,
    String objectId,
    String ruleId,
  ) async {
    final intId = _idFor('$objectType:$objectId:$ruleId');
    await notif.cancel(intId);
    await alarm.cancel(intId);
    await email.cancel(intId);
  }

  Future<void> _syncRuleObjects({
    required String objectType,
    required Map<String, Map<String, _ResolvedRule>> wanted,
    required Map<String, Map<String, _ScheduledRule>> scheduled,
    required Future<void> Function(String objectId) cancelLegacy,
  }) async {
    final nextScheduled = <String, Map<String, _ScheduledRule>>{};

    for (final objectId in scheduled.keys.toList()) {
      final priorRules = scheduled[objectId] ?? const {};
      final nextRules = wanted[objectId];
      if (nextRules == null) {
        await _cancelRuleObjects(objectType, objectId, priorRules.keys);
        await cancelLegacy(objectId);
        continue;
      }

      final kept = <String, _ScheduledRule>{};
      for (final priorEntry in priorRules.entries) {
        if (!nextRules.containsKey(priorEntry.key)) {
          await _cancelRule(objectType, objectId, priorEntry.key);
        }
      }

      for (final nextEntry in nextRules.entries) {
        final nextRule = nextEntry.value;
        final prior = priorRules[nextEntry.key];
        final needsCancel =
            prior != null &&
            (prior.kind != nextRule.kind ||
                prior.mode != nextRule.mode ||
                prior.scope != nextRule.scope);
        if (needsCancel) {
          await _cancelRule(objectType, objectId, nextEntry.key);
        }
      }

      await cancelLegacy(objectId);
      for (final nextRule in nextRules.values) {
        final ok = await _dispatchRule(nextRule);
        if (ok) {
          kept[nextRule.ruleId] = _ScheduledRule(
            kind: nextRule.kind,
            mode: nextRule.mode,
            scope: nextRule.scope,
          );
        } else {
          final prior = priorRules[nextRule.ruleId];
          if (prior != null &&
              prior.kind == nextRule.kind &&
              prior.mode == nextRule.mode &&
              prior.scope == nextRule.scope) {
            kept[nextRule.ruleId] = prior;
          }
        }
      }

      if (kept.isNotEmpty) {
        nextScheduled[objectId] = kept;
      }
    }

    for (final entry in wanted.entries) {
      final objectId = entry.key;
      if (scheduled.containsKey(objectId)) continue;

      final nextRules = entry.value;
      final kept = <String, _ScheduledRule>{};
      await cancelLegacy(objectId);
      for (final nextRule in nextRules.values) {
        final ok = await _dispatchRule(nextRule);
        if (ok) {
          kept[nextRule.ruleId] = _ScheduledRule(
            kind: nextRule.kind,
            mode: nextRule.mode,
            scope: nextRule.scope,
          );
        }
      }
      if (kept.isNotEmpty) {
        nextScheduled[objectId] = kept;
      }
    }

    scheduled
      ..clear()
      ..addAll(nextScheduled);
  }

  // -------------------------------------------------------------------------
  // 内部：决定什么时候、以什么通道派发
  // -------------------------------------------------------------------------

  List<_ResolvedRule> _resolveTodoRules(TodoItem t) {
    final plan = _effectiveTodoPlan(t);
    if (!plan.enabled || plan.rules.isEmpty) return const <_ResolvedRule>[];
    final now = DateTime.now();
    final resolved = <_ResolvedRule>[];
    for (final rule in plan.rules) {
      if (!rule.enabled) continue;
      final next = _resolveTodoRule(t, rule, now);
      if (next != null) resolved.add(next);
    }
    return resolved;
  }

  ReminderPlan _effectiveTodoPlan(TodoItem t) {
    if (t.reminderPlan.enabled && t.reminderPlan.rules.isNotEmpty) {
      return t.reminderPlan;
    }
    if (t.reminder.enabled) {
      return ReminderPlan.fromLegacy(t.reminder);
    }
    // ignore: deprecated_member_use_from_same_package
    if (t.hasReminder) {
      final anchor = t.reminderAt ?? t.dueDate;
      if (anchor == null) return const ReminderPlan.disabled();
      return ReminderPlan(
        enabled: true,
        rules: [
          ReminderRule(
            id: 'legacy-${t.id}',
            enabled: true,
            type: ReminderRuleType.absolute,
            kind: ReminderKind.push,
            hour: anchor.hour,
            minute: anchor.minute,
          ),
        ],
      );
    }
    return const ReminderPlan.disabled();
  }

  _ResolvedRule? _resolveTodoRule(TodoItem t, ReminderRule rule, DateTime now) {
    switch (rule.type) {
      case ReminderRuleType.absolute:
        final payload = _todoPayload(t.id, rule.kind);
        final anchor = t.dueDate ?? t.reminderAt;
        if (anchor == null) return null;
        final when = _dateAtTime(
          anchor,
          rule.hour ?? anchor.hour,
          rule.minute ?? anchor.minute,
        );
        if (!when.isAfter(now)) return null;
        return _buildOnceRule(
          objectType: 'todo',
          objectId: t.id,
          rule: rule,
          title: _titleFor('todo', rule.type, rule.kind),
          body: t.title,
          payload: payload,
          when: when,
        );
      case ReminderRuleType.relativeToDue:
        final payload = _todoPayload(t.id, rule.kind);
        final anchor = t.dueDate ?? t.reminderAt;
        if (anchor == null) return null;
        final base = _dateAtTime(
          anchor,
          rule.hour ?? anchor.hour,
          rule.minute ?? anchor.minute,
        );
        final when = base.add(Duration(minutes: rule.offsetMinutes ?? 0));
        if (!when.isAfter(now)) return null;
        return _buildOnceRule(
          objectType: 'todo',
          objectId: t.id,
          rule: rule,
          title: _titleFor('todo', rule.type, rule.kind),
          body: t.title,
          payload: payload,
          when: when,
        );
      case ReminderRuleType.dailyTime:
        final payload = _todoPayload(t.id, rule.kind);
        if (rule.hour == null || rule.minute == null) return null;
        return _buildRepeatingRule(
          objectType: 'todo',
          objectId: t.id,
          rule: rule,
          title: _titleFor('todo', rule.type, rule.kind),
          body: t.title,
          payload: payload,
          hour: rule.hour!,
          minute: rule.minute!,
          weekdays: const <int>[],
        );
      case ReminderRuleType.weeklyTime:
        final payload = _todoPayload(t.id, rule.kind);
        if (rule.hour == null || rule.minute == null || rule.weekdays.isEmpty) {
          return null;
        }
        return _buildRepeatingRule(
          objectType: 'todo',
          objectId: t.id,
          rule: rule,
          title: _titleFor('todo', rule.type, rule.kind),
          body: t.title,
          payload: payload,
          hour: rule.hour!,
          minute: rule.minute!,
          weekdays: _normalizedWeekdays(rule.weekdays),
        );
    }
  }

  List<_ResolvedRule> _resolveGoalRules(GoalItem g) {
    final plan = g.reminderPlan.enabled && g.reminderPlan.rules.isNotEmpty
        ? g.reminderPlan
        : g.reminder.enabled
        ? ReminderPlan.fromLegacy(g.reminder)
        : const ReminderPlan.disabled();
    if (!plan.enabled || plan.rules.isEmpty) return const <_ResolvedRule>[];
    final now = DateTime.now();
    final resolved = <_ResolvedRule>[];
    for (final rule in plan.rules) {
      if (!rule.enabled) continue;
      final next = _resolveGoalRule(g, rule, now);
      if (next != null) resolved.add(next);
    }
    return resolved;
  }

  _ResolvedRule? _resolveGoalRule(GoalItem g, ReminderRule rule, DateTime now) {
    final payload = 'duoyi://goal/${g.id}';
    switch (rule.type) {
      case ReminderRuleType.absolute:
        final anchorDate = _goalAnchorDate(g, now);
        final when = _dateAtTime(
          anchorDate,
          rule.hour ?? anchorDate.hour,
          rule.minute ?? anchorDate.minute,
        );
        if (!when.isAfter(now)) {
          final tomorrow = DateTime(
            now.year,
            now.month,
            now.day,
          ).add(const Duration(days: 1));
          final fallback = _dateAtTime(
            tomorrow,
            rule.hour ?? anchorDate.hour,
            rule.minute ?? anchorDate.minute,
          );
          if (!fallback.isAfter(now)) return null;
          return _buildOnceRule(
            objectType: 'goal',
            objectId: g.id,
            rule: rule,
            title: _titleFor('goal', rule.type, rule.kind),
            body: g.title,
            payload: payload,
            when: fallback,
          );
        }
        return _buildOnceRule(
          objectType: 'goal',
          objectId: g.id,
          rule: rule,
          title: _titleFor('goal', rule.type, rule.kind),
          body: g.title,
          payload: payload,
          when: when,
        );
      case ReminderRuleType.relativeToDue:
        final anchor = g.targetDate ?? g.startDate;
        if (anchor == null) return null;
        final base = _dateAtTime(
          anchor,
          rule.hour ?? anchor.hour,
          rule.minute ?? anchor.minute,
        );
        final when = base.add(Duration(minutes: rule.offsetMinutes ?? 0));
        if (!when.isAfter(now)) return null;
        return _buildOnceRule(
          objectType: 'goal',
          objectId: g.id,
          rule: rule,
          title: _titleFor('goal', rule.type, rule.kind),
          body: g.title,
          payload: payload,
          when: when,
        );
      case ReminderRuleType.dailyTime:
        if (rule.hour == null || rule.minute == null) return null;
        return _buildRepeatingRule(
          objectType: 'goal',
          objectId: g.id,
          rule: rule,
          title: _titleFor('goal', rule.type, rule.kind),
          body: g.title,
          payload: payload,
          hour: rule.hour!,
          minute: rule.minute!,
          weekdays: const <int>[],
        );
      case ReminderRuleType.weeklyTime:
        if (rule.hour == null || rule.minute == null || rule.weekdays.isEmpty) {
          return null;
        }
        return _buildRepeatingRule(
          objectType: 'goal',
          objectId: g.id,
          rule: rule,
          title: _titleFor('goal', rule.type, rule.kind),
          body: g.title,
          payload: payload,
          hour: rule.hour!,
          minute: rule.minute!,
          weekdays: _normalizedWeekdays(rule.weekdays),
        );
    }
  }

  _ResolvedRule _buildOnceRule({
    required String objectType,
    required String objectId,
    required ReminderRule rule,
    required String title,
    required String body,
    required String payload,
    required DateTime when,
  }) {
    return _ResolvedRule(
      objectType: objectType,
      objectId: objectId,
      ruleId: rule.id,
      kind: rule.kind,
      mode: _DispatchMode.once,
      ruleType: rule.type,
      title: title,
      body: body,
      payload: payload,
      fullScreen: rule.fullScreen,
      vibrate: rule.vibrate,
      snoozeMinutes: rule.snoozeMinutes,
      repeatCount: rule.repeatCount,
      when: when,
      scope: 'once',
    );
  }

  _ResolvedRule _buildRepeatingRule({
    required String objectType,
    required String objectId,
    required ReminderRule rule,
    required String title,
    required String body,
    required String payload,
    required int hour,
    required int minute,
    required List<int> weekdays,
  }) {
    final normalized = weekdays.isEmpty ? const <int>[] : weekdays;
    final scope = normalized.isEmpty
        ? 'daily'
        : 'weekly:${normalized.join(',')}';
    return _ResolvedRule(
      objectType: objectType,
      objectId: objectId,
      ruleId: rule.id,
      kind: rule.kind,
      mode: _DispatchMode.repeating,
      ruleType: rule.type,
      title: title,
      body: body,
      payload: payload,
      fullScreen: rule.fullScreen,
      vibrate: rule.vibrate,
      snoozeMinutes: rule.snoozeMinutes,
      repeatCount: rule.repeatCount,
      hour: hour,
      minute: minute,
      weekdays: normalized,
      scope: scope,
    );
  }

  Future<bool> _dispatchRule(_ResolvedRule rule) async {
    try {
      switch (rule.mode) {
        case _DispatchMode.once:
          if (rule.when == null) return false;
          return await _dispatch(
            kind: rule.kind,
            payload: _DispatchPayload(
              id: _idFor(rule.key),
              title: rule.title,
              body: rule.body,
              when: rule.when!,
              payload: rule.payload,
              fullScreen: rule.fullScreen,
              vibrate: rule.vibrate,
              snoozeMinutes: rule.snoozeMinutes,
              repeatCount: rule.repeatCount,
            ),
          );
        case _DispatchMode.repeating:
          return await _dispatchRepeating(rule);
      }
    } catch (e, st) {
      debugPrint(
        '[ReminderScheduler] dispatch failed for ${rule.key}: $e\n$st',
      );
      return false;
    }
  }

  // -------------------------------------------------------------------------
  // 内部：时间与文案
  // -------------------------------------------------------------------------

  DateTime _dateAtTime(DateTime date, int hour, int minute) {
    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  DateTime _countdownReminderAt(CountdownItem item) {
    final target = DateTime(
      item.targetDate.year,
      item.targetDate.month,
      item.targetDate.day,
      item.remindHour,
      item.remindMinute,
    );
    return target.subtract(Duration(days: item.remindDaysBefore));
  }

  String _countdownScope(CountdownItem item, DateTime when) {
    return '${when.millisecondsSinceEpoch}:${item.title}:${item.remindDaysBefore}:${item.remindHour}:${item.remindMinute}';
  }

  List<int> _normalizedWeekdays(List<int> weekdays) {
    final normalized = <int>{};
    for (final day in weekdays) {
      if (day >= 1 && day <= 7) normalized.add(day);
    }
    final result = normalized.toList()..sort();
    return result;
  }

  String _titleFor(
    String objectType,
    ReminderRuleType type,
    ReminderKind kind,
  ) {
    final subject = objectType == 'goal' ? '目标' : '待办';
    final prefix = switch (kind) {
      ReminderKind.alarm => '⏰',
      ReminderKind.email => '✉️',
      ReminderKind.push => '🔔',
    };
    return switch (type) {
      ReminderRuleType.absolute => '$prefix $subject提醒',
      ReminderRuleType.relativeToDue => '$prefix $subject提前提醒',
      ReminderRuleType.dailyTime => '$prefix 每日$subject提醒',
      ReminderRuleType.weeklyTime => '$prefix 每周$subject提醒',
    };
  }

  String _todoPayload(String id, ReminderKind kind) {
    if (kind == ReminderKind.alarm) return 'duoyi://todo/$id?confirm=1';
    return 'duoyi://todo/$id';
  }

  String? _fallbackPayload(String? payload) {
    if (payload == null) return null;
    final uri = Uri.tryParse(payload);
    if (uri == null || uri.host != 'todo') return payload;
    final id = uri.pathSegments.isEmpty ? '' : uri.pathSegments.first;
    if (id.isEmpty) return payload;
    return 'duoyi://todo/$id';
  }

  /// 目标锚定日：优先用今日；若 `startDate` 在未来，用 `startDate`。
  DateTime _goalAnchorDate(GoalItem g, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final start = g.startDate;
    if (start != null) {
      final startDay = DateTime(start.year, start.month, start.day);
      if (startDay.isAfter(today)) return startDay;
    }
    return today;
  }

  // -------------------------------------------------------------------------
  // 内部：字符串 id → 稳定 int（与 `NotificationService._idFor` 等价）
  // -------------------------------------------------------------------------

  int _idFor(String key) {
    int h = 0;
    for (final c in key.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return h;
  }
}
