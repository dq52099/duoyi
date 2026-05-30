import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/anniversary.dart';
import '../models/countdown.dart';
import '../models/goal.dart';
import '../models/habit.dart';
import '../models/todo.dart';
import 'alarm_service.dart';
import 'notification_permission_exception.dart';
import 'reminder_sinks.dart';

const Duration _sameMinuteReminderGrace = Duration(seconds: 70);

class TodoReminderPreflightIssue {
  final String title;
  final String message;
  final bool blocking;
  final DateTime? scheduledTime;

  const TodoReminderPreflightIssue({
    required this.title,
    required this.message,
    this.blocking = true,
    this.scheduledTime,
  });
}

class TodoReminderPreflightResult {
  final bool hasEnabledPlan;
  final Set<ReminderKind> kinds;
  final DateTime? firstScheduledTime;
  final List<TodoReminderPreflightIssue> issues;

  const TodoReminderPreflightResult({
    required this.hasEnabledPlan,
    required this.kinds,
    required this.firstScheduledTime,
    required this.issues,
  });

  bool get ok => issues.every((issue) => !issue.blocking);
  TodoReminderPreflightIssue? get blockingIssue {
    for (final issue in issues) {
      if (issue.blocking) return issue;
    }
    return null;
  }
}

TodoReminderPreflightResult preflightTodoReminderPlan(
  TodoItem todo, {
  DateTime? now,
}) {
  final effectiveNow = now ?? DateTime.now();
  final plan = _effectiveTodoPlanForPreflight(todo);
  final enabledRules = plan.enabled
      ? plan.rules
            .where((rule) => rule.enabled && rule.kind != ReminderKind.off)
            .toList(growable: false)
      : const <ReminderRule>[];
  if (enabledRules.isEmpty) {
    return const TodoReminderPreflightResult(
      hasEnabledPlan: false,
      kinds: <ReminderKind>{},
      firstScheduledTime: null,
      issues: <TodoReminderPreflightIssue>[],
    );
  }

  final kinds = <ReminderKind>{};
  final issues = <TodoReminderPreflightIssue>[];
  DateTime? firstScheduledTime;
  var deliverableRules = 0;

  for (final rule in enabledRules) {
    kinds.add(rule.kind);
    switch (rule.type) {
      case ReminderRuleType.absolute:
      case ReminderRuleType.relativeToDue:
        final anchor = todo.dueDate ?? todo.reminderAt;
        if (anchor == null) {
          issues.add(
            const TodoReminderPreflightIssue(
              title: '待办提醒注册失败',
              message: '一次性提醒需要截止日期或提醒日期。请先设置未来的日期。',
            ),
          );
          continue;
        }
        final base = _dateAtTimeForPreflight(
          anchor,
          rule.hour ?? anchor.hour,
          rule.minute ?? anchor.minute,
        );
        final when = rule.type == ReminderRuleType.relativeToDue
            ? base.add(Duration(minutes: rule.offsetMinutes ?? 0))
            : base;
        final scheduledWhen = _coerceJustMissedOneShotReminder(
          when,
          effectiveNow,
        );
        if (scheduledWhen == null) {
          issues.add(
            TodoReminderPreflightIssue(
              title: '待办提醒注册失败',
              message: '提醒时间已过去，未注册到系统通知。请把提醒时间改到未来时间。',
              scheduledTime: when,
            ),
          );
          continue;
        }
        deliverableRules++;
        if (firstScheduledTime == null ||
            scheduledWhen.isBefore(firstScheduledTime)) {
          firstScheduledTime = scheduledWhen;
        }
        break;
      case ReminderRuleType.dailyTime:
        if (!_validTimeForPreflight(rule.hour, rule.minute)) {
          issues.add(
            const TodoReminderPreflightIssue(
              title: '重复提醒注册失败',
              message: '重复提醒缺少有效时间，请重新选择提醒时间。',
            ),
          );
          continue;
        }
        deliverableRules++;
        break;
      case ReminderRuleType.weeklyTime:
        if (!_validTimeForPreflight(rule.hour, rule.minute) ||
            rule.weekdays.isEmpty) {
          issues.add(
            const TodoReminderPreflightIssue(
              title: '每周提醒注册失败',
              message: '每周提醒需要有效时间和至少一个星期。请重新选择提醒规则。',
            ),
          );
          continue;
        }
        deliverableRules++;
        break;
    }
  }

  if (deliverableRules == 0 && issues.isEmpty) {
    issues.add(
      const TodoReminderPreflightIssue(
        title: '待办提醒注册失败',
        message: '提醒计划没有可注册的规则，请重新设置提醒。',
      ),
    );
  }

  return TodoReminderPreflightResult(
    hasEnabledPlan: true,
    kinds: kinds,
    firstScheduledTime: firstScheduledTime,
    issues: issues,
  );
}

ReminderPlan _effectiveTodoPlanForPreflight(TodoItem t) {
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

DateTime _dateAtTimeForPreflight(DateTime date, int hour, int minute) {
  return DateTime(date.year, date.month, date.day, hour, minute);
}

bool _validTimeForPreflight(int? hour, int? minute) {
  return hour != null &&
      minute != null &&
      hour >= 0 &&
      hour <= 23 &&
      minute >= 0 &&
      minute <= 59;
}

DateTime? _coerceJustMissedOneShotReminder(DateTime when, DateTime now) {
  if (when.isAfter(now)) return when;
  final missedBy = now.difference(when);
  final sameLocalMinute =
      when.year == now.year &&
      when.month == now.month &&
      when.day == now.day &&
      when.hour == now.hour &&
      when.minute == now.minute;
  if (sameLocalMinute &&
      !missedBy.isNegative &&
      missedBy <= _sameMinuteReminderGrace) {
    return DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
    ).add(const Duration(minutes: 1));
  }
  return null;
}

DateTime? _resolveOneShotReminderTime(
  DateTime when,
  DateTime now, {
  required bool allowJustMissed,
}) {
  if (allowJustMissed) {
    return _coerceJustMissedOneShotReminder(when, now);
  }
  return when.isAfter(now) ? when : null;
}

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
  final String fingerprint;

  const _ScheduledRule({
    required this.kind,
    required this.mode,
    required this.scope,
    required this.fingerprint,
  });
}

enum _DispatchMode { once, repeating }

abstract class ReminderScheduleRegistry {
  const ReminderScheduleRegistry();

  Future<Map<String, Set<int>>> idsByObject(String objectType);

  Future<void> replaceObject(String objectType, String objectId, Set<int> ids);

  Future<void> removeObject(String objectType, String objectId);
}

class SharedPreferencesReminderScheduleRegistry
    implements ReminderScheduleRegistry {
  static const _storageKey = 'reminder_scheduler_registry_v1';

  const SharedPreferencesReminderScheduleRegistry();

  @override
  Future<Map<String, Set<int>>> idsByObject(String objectType) async {
    final all = await _readAll();
    return {
      for (final entry
          in (all[objectType] ?? const <String, Set<int>>{}).entries)
        entry.key: Set<int>.from(entry.value),
    };
  }

  @override
  Future<void> replaceObject(
    String objectType,
    String objectId,
    Set<int> ids,
  ) async {
    final normalized = ids.where((id) => id != 0).toSet();
    if (normalized.isEmpty) {
      await removeObject(objectType, objectId);
      return;
    }
    final all = await _readAll();
    final typeMap = all.putIfAbsent(objectType, () => <String, Set<int>>{});
    typeMap[objectId] = normalized;
    await _writeAll(all);
  }

  @override
  Future<void> removeObject(String objectType, String objectId) async {
    final all = await _readAll();
    final typeMap = all[objectType];
    if (typeMap == null) return;
    typeMap.remove(objectId);
    if (typeMap.isEmpty) all.remove(objectType);
    await _writeAll(all);
  }

  Future<SharedPreferences?> _prefsOrNull() async {
    var bindingInitialized = true;
    assert(() {
      bindingInitialized = BindingBase.debugBindingType() != null;
      return true;
    }());
    if (!bindingInitialized) return null;
    try {
      return await SharedPreferences.getInstance();
    } catch (e, st) {
      debugPrint(
        '[ReminderScheduler] reminder registry prefs unavailable: $e\n$st',
      );
      return null;
    }
  }

  Future<Map<String, Map<String, Set<int>>>> _readAll() async {
    final prefs = await _prefsOrNull();
    if (prefs == null) return <String, Map<String, Set<int>>>{};
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return <String, Map<String, Set<int>>>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, Map<String, Set<int>>>{};
      final result = <String, Map<String, Set<int>>>{};
      decoded.forEach((type, rawObjects) {
        if (type is! String || rawObjects is! Map) return;
        final objects = <String, Set<int>>{};
        rawObjects.forEach((objectId, rawIds) {
          if (objectId is! String || rawIds is! List) return;
          final ids = <int>{};
          for (final rawId in rawIds) {
            final id = rawId is int
                ? rawId
                : rawId is num
                ? rawId.toInt()
                : null;
            if (id != null && id != 0) ids.add(id);
          }
          if (ids.isNotEmpty) objects[objectId] = ids;
        });
        if (objects.isNotEmpty) result[type] = objects;
      });
      return result;
    } catch (e, st) {
      debugPrint(
        '[ReminderScheduler] reminder registry decode failed: $e\n$st',
      );
      return <String, Map<String, Set<int>>>{};
    }
  }

  Future<void> _writeAll(Map<String, Map<String, Set<int>>> all) async {
    final prefs = await _prefsOrNull();
    if (prefs == null) return;
    final encoded = <String, Map<String, List<int>>>{};
    for (final typeEntry in all.entries) {
      final objects = <String, List<int>>{};
      for (final objectEntry in typeEntry.value.entries) {
        final ids = objectEntry.value.where((id) => id != 0).toList()..sort();
        if (ids.isNotEmpty) objects[objectEntry.key] = ids;
      }
      if (objects.isNotEmpty) encoded[typeEntry.key] = objects;
    }
    if (encoded.isEmpty) {
      await prefs.remove(_storageKey);
    } else {
      await prefs.setString(_storageKey, jsonEncode(encoded));
    }
  }
}

@visibleForTesting
class InMemoryReminderScheduleRegistry implements ReminderScheduleRegistry {
  final Map<String, Map<String, Set<int>>> _store = {};

  @override
  Future<Map<String, Set<int>>> idsByObject(String objectType) async {
    return {
      for (final entry
          in (_store[objectType] ?? const <String, Set<int>>{}).entries)
        entry.key: Set<int>.from(entry.value),
    };
  }

  @override
  Future<void> replaceObject(
    String objectType,
    String objectId,
    Set<int> ids,
  ) async {
    final normalized = ids.where((id) => id != 0).toSet();
    if (normalized.isEmpty) {
      await removeObject(objectType, objectId);
      return;
    }
    _store.putIfAbsent(objectType, () => <String, Set<int>>{})[objectId] =
        normalized;
  }

  @override
  Future<void> removeObject(String objectType, String objectId) async {
    final typeMap = _store[objectType];
    if (typeMap == null) return;
    typeMap.remove(objectId);
    if (typeMap.isEmpty) _store.remove(objectType);
  }
}

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

  String get fingerprint {
    final weekdayPart = weekdays.isEmpty ? '-' : weekdays.join(',');
    final whenPart = when?.toIso8601String() ?? '-';
    final hourPart = hour?.toString() ?? '-';
    final minutePart = minute?.toString() ?? '-';
    return [
      kind.index,
      mode.name,
      ruleType.index,
      scope,
      title,
      body,
      payload,
      fullScreen ? 'fs1' : 'fs0',
      vibrate ? 'v1' : 'v0',
      snoozeMinutes,
      repeatCount,
      whenPart,
      hourPart,
      minutePart,
      weekdayPart,
    ].join('|');
  }

  String get deliveryFingerprint {
    final weekdayPart = weekdays.isEmpty ? '-' : weekdays.join(',');
    final whenPart = when?.toIso8601String() ?? '-';
    final hourPart = hour?.toString() ?? '-';
    final minutePart = minute?.toString() ?? '-';
    return [
      kind.index,
      mode.name,
      scope,
      body,
      payload,
      fullScreen ? 'fs1' : 'fs0',
      vibrate ? 'v1' : 'v0',
      snoozeMinutes,
      repeatCount,
      whenPart,
      hourPart,
      minutePart,
      weekdayPart,
    ].join('|');
  }

  String get logicalDeliveryFingerprint {
    final weekdayPart = weekdays.isEmpty ? '-' : weekdays.join(',');
    final whenPart = when?.toIso8601String() ?? '-';
    final hourPart = hour?.toString() ?? '-';
    final minutePart = minute?.toString() ?? '-';
    return [
      objectType,
      objectId,
      mode.name,
      scope,
      body,
      whenPart,
      hourPart,
      minutePart,
      weekdayPart,
    ].join('|');
  }
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
  final ReminderPopupSink popup;
  final ReminderScheduleRegistry registry;

  /// 上一轮已下发的 todo / goal rule → 通道与调度形态。
  final Map<String, Map<String, _ScheduledRule>> _scheduledTodoRules = {};
  final Map<String, Map<String, _ScheduledRule>> _scheduledGoalRules = {};
  final Map<String, String> _scheduledHabitScopes = {};
  final Map<String, String> _scheduledAnniversaryScopes = {};
  final Map<String, String> _scheduledCountdownScopes = {};
  Future<void> _syncQueue = Future<void>.value();

  /// [notif] 必传；[alarm] 默认取 `AlarmService.instance` 单例，便于测试时
  /// 注入 fake。[popup] 未注入时默认落到 [notif] 作为系统通知兜底，避免
  /// popup 规则被空实现缓存为“已调度”。[email] 默认 no-op，未配置邮件
  /// 服务时不会误发本地通知。各通道均以 sink 接口表达，便于属性测试注入。
  ReminderScheduler(
    this.notif, {
    ReminderAlarmSink? alarm,
    ReminderEmailSink? email,
    ReminderPopupSink? popup,
    ReminderScheduleRegistry? registry,
  }) : alarm = alarm ?? AlarmService.instance,
       email = email ?? const NoopReminderEmailSink(),
       popup = popup ?? NotificationFallbackReminderPopupSink(notif),
       registry = registry ?? const SharedPreferencesReminderScheduleRegistry();

  @visibleForTesting
  int debugScheduledTodoRuleCount(String todoId) {
    return _scheduledTodoRules[todoId]?.length ?? 0;
  }

  // -------------------------------------------------------------------------
  // 公共 API
  // -------------------------------------------------------------------------

  /// 按最新的 [todos] 幂等地重新同步待办提醒。
  Future<void> syncTodos(
    Iterable<TodoItem> todos, {
    bool allowJustMissedOneShotReminders = true,
  }) async {
    final snapshot = todos.toList(growable: false);
    await _runSerialized(
      () => _syncTodosLocked(
        snapshot,
        allowJustMissedOneShotReminders: allowJustMissedOneShotReminders,
      ),
    );
  }

  Future<void> _syncTodosLocked(
    Iterable<TodoItem> todos, {
    required bool allowJustMissedOneShotReminders,
  }) async {
    final wanted = <String, Map<String, _ResolvedRule>>{};
    for (final t in todos) {
      if (t.isCompleted) {
        await _cancelCurrentTodoPlan(t);
        continue;
      }
      final resolved = _resolveTodoRules(
        t,
        allowJustMissedOneShotReminders: allowJustMissedOneShotReminders,
      );
      if (resolved.isEmpty) {
        _recordUnresolvedTodoReminderIssue(t);
        await _cancelCurrentTodoPlan(t);
        continue;
      }
      wanted[t.id] = {for (final rule in resolved) rule.ruleId: rule};
    }
    final blocked = await _sweepRuleRegistry(
      objectType: 'todo',
      wanted: wanted,
    );
    wanted.removeWhere((objectId, _) => blocked.contains(objectId));
    await _syncRuleObjects(
      objectType: 'todo',
      wanted: wanted,
      scheduled: _scheduledTodoRules,
      cancelLegacy: _cancelTodoLegacy,
    );
  }

  void _recordUnresolvedTodoReminderIssue(TodoItem todo) {
    final issueSink = notif is ReminderScheduleIssueSink
        ? notif as ReminderScheduleIssueSink
        : null;
    if (issueSink == null) return;
    final preflight = preflightTodoReminderPlan(todo);
    if (!preflight.hasEnabledPlan || preflight.ok) return;
    final blocking = preflight.blockingIssue;
    final issue =
        blocking ?? (preflight.issues.isEmpty ? null : preflight.issues.first);
    if (issue == null) return;
    issueSink.recordReminderScheduleIssue(
      title: issue.title,
      message: issue.message,
      scheduledTime: issue.scheduledTime,
      relatedId: todo.id,
      blocking: issue.blocking,
    );
  }

  /// 按最新的 [habits] 幂等地重新同步习惯提醒。
  ///
  /// 习惯提醒按用户选择走通知、应用内弹窗或柔和强提醒闹钟。闹钟权限不足时
  /// 降级为普通 push，确保不会静默丢提醒。
  Future<void> syncHabits(Iterable<Habit> habits) async {
    final snapshot = habits.toList(growable: false);
    await _runSerialized(() => _syncHabitsLocked(snapshot));
  }

  Future<void> _syncHabitsLocked(Iterable<Habit> habits) async {
    final wanted = <String, Habit>{};
    final handledInactiveHabitIds = <String>{};
    for (final h in habits) {
      final plan = _effectiveHabitPlan(h);
      final rule = plan.primaryRule;
      if (!plan.enabled ||
          rule == null ||
          !rule.enabled ||
          rule.kind == ReminderKind.off) {
        handledInactiveHabitIds.add(h.id);
        final cancelled = await _cancelHabit(h.id);
        if (cancelled) {
          _scheduledHabitScopes.remove(h.id);
          await registry.removeObject('habit', h.id);
        }
        continue;
      }
      wanted[h.id] = h;
    }
    final scopes = <String, String>{};
    for (final h in wanted.values) {
      scopes[h.id] = _habitScope(h);
    }
    final blockedHabitIdsFromRegistry = await _sweepSingleRegistry(
      objectType: 'habit',
      wantedIdsByObject: {
        for (final h in wanted.values) h.id: _habitRegistryIds(h),
      },
    );
    wanted.removeWhere((id, _) => blockedHabitIdsFromRegistry.contains(id));
    scopes.removeWhere((id, _) => blockedHabitIdsFromRegistry.contains(id));

    final blockedHabitIds = <String>{};
    for (final id in _scheduledHabitScopes.keys.toList()) {
      if (handledInactiveHabitIds.contains(id)) continue;
      final nextScope = scopes[id];
      if (nextScope == null || _scheduledHabitScopes[id] != nextScope) {
        final cancelled = await _cancelHabit(id);
        if (cancelled) {
          _scheduledHabitScopes.remove(id);
          await registry.removeObject('habit', id);
        } else {
          blockedHabitIds.add(id);
        }
      }
    }
    for (final h in wanted.values) {
      if (blockedHabitIds.contains(h.id)) continue;
      if (!_scheduledHabitScopes.containsKey(h.id)) {
        final swept = await _cancelHabit(h.id);
        if (!swept) continue;
      }
      final scope = scopes[h.id]!;
      if (_scheduledHabitScopes[h.id] == scope) {
        if (await _habitStillPending(h)) {
          await registry.replaceObject('habit', h.id, _habitRegistryIds(h));
          continue;
        }
        final cancelled = await _cancelHabit(h.id);
        if (!cancelled) continue;
        _scheduledHabitScopes.remove(h.id);
        await registry.removeObject('habit', h.id);
      }
      final scheduled = await _scheduleHabit(h);
      if (scheduled) {
        _scheduledHabitScopes[h.id] = scope;
        await registry.replaceObject('habit', h.id, _habitRegistryIds(h));
      }
    }
  }

  Future<bool> _scheduleHabit(Habit habit) async {
    final plan = _effectiveHabitPlan(habit);
    final rule = plan.primaryRule;
    if (rule == null || !rule.enabled || rule.kind == ReminderKind.off) {
      return false;
    }
    final hour = rule.hour;
    final minute = rule.minute;
    if (hour == null || minute == null) return false;
    final weekdays = _habitWeekdays(habit, rule);
    final id = _idFor('habit_${habit.id}');
    final payload = 'duoyi://habit/${habit.id}?confirm=1';
    final title = _habitTitle(rule.kind);
    final body = '${habit.name} 到时间了，点开确认打卡';

    switch (rule.kind) {
      case ReminderKind.push:
        return _scheduleHabitPush(habit, hour, minute, weekdays);
      case ReminderKind.popup:
        try {
          await popup.scheduleRepeating(
            id: id,
            title: title,
            body: body,
            hour: hour,
            minute: minute,
            weekdays: weekdays.isEmpty ? null : weekdays,
            payload: payload,
          );
          return true;
        } catch (e, st) {
          debugPrint(
            '[ReminderScheduler] habit popup dispatch failed for ${habit.id}: $e\n$st',
          );
          return false;
        }
      case ReminderKind.alarm:
        try {
          await alarm.scheduleDailyFullScreen(
            id: id,
            title: title,
            body: body,
            hour: hour,
            minute: minute,
            weekdays: weekdays.isEmpty ? null : weekdays,
            payload: payload,
            fullScreen: rule.fullScreen,
            vibrate: rule.vibrate,
            snoozeMinutes: rule.snoozeMinutes,
            repeatCount: rule.repeatCount,
          );
          return true;
        } on AlarmPermissionDeniedException catch (e) {
          debugPrint(
            '[ReminderScheduler] habit alarm permission denied for ${habit.id}: $e',
          );
          if (await _alarmQueueAlreadyOwns(
            label: 'habit:${habit.id}',
            expected: _expectedRepeatingPendingIds(id, weekdays),
            acceptedExpectedSets: _acceptedRepeatingPendingIdSets(
              kind: ReminderKind.alarm,
              base: id,
              weekdays: weekdays,
            ),
          )) {
            return true;
          }
          return _scheduleHabitPush(habit, hour, minute, weekdays);
        } on NotificationPermissionDeniedException catch (e) {
          debugPrint(
            '[ReminderScheduler] habit alarm notification permission denied for ${habit.id}: $e',
          );
          if (await _alarmQueueAlreadyOwns(
            label: 'habit:${habit.id}',
            expected: _expectedRepeatingPendingIds(id, weekdays),
            acceptedExpectedSets: _acceptedRepeatingPendingIdSets(
              kind: ReminderKind.alarm,
              base: id,
              weekdays: weekdays,
            ),
          )) {
            return true;
          }
          return _scheduleHabitPush(habit, hour, minute, weekdays);
        } on AlarmQueueHandoffException catch (e) {
          debugPrint(
            '[ReminderScheduler] habit alarm queue handoff failed for ${habit.id}: $e',
          );
          return false;
        } catch (e, st) {
          debugPrint(
            '[ReminderScheduler] habit alarm dispatch failed for ${habit.id}: $e\n$st',
          );
          if (await _alarmQueueAlreadyOwns(
            label: 'habit:${habit.id}',
            expected: _expectedRepeatingPendingIds(id, weekdays),
            acceptedExpectedSets: _acceptedRepeatingPendingIdSets(
              kind: ReminderKind.alarm,
              base: id,
              weekdays: weekdays,
            ),
          )) {
            return true;
          }
          return _scheduleHabitPush(habit, hour, minute, weekdays);
        }
      case ReminderKind.email:
      case ReminderKind.off:
        return false;
    }
  }

  Future<bool> _scheduleHabitPush(
    Habit habit,
    int hour,
    int minute,
    List<int> weekdays,
  ) async {
    try {
      await notif.scheduleHabitReminder(
        habitId: habit.id,
        habitName: habit.name,
        hour: hour,
        minute: minute,
        weekdays: weekdays.isEmpty ? null : weekdays,
      );
      return true;
    } on NotificationPermissionDeniedException catch (fallbackError) {
      debugPrint(
        '[ReminderScheduler] habit notification permission denied for ${habit.id}: $fallbackError',
      );
      return false;
    } catch (fallbackError, st) {
      debugPrint(
        '[ReminderScheduler] habit notification dispatch failed for ${habit.id}: $fallbackError\n$st',
      );
      return false;
    }
  }

  Future<bool> _cancelHabit(String habitId) async {
    final id = _idFor('habit_$habitId');
    var ok = true;
    ok =
        await _cancelSafely(
          'habit notification:$habitId',
          () => notif.cancelHabitReminder(habitId),
        ) &&
        ok;
    ok =
        await _cancelSafely('habit alarm:$habitId', () => alarm.cancel(id)) &&
        ok;
    ok =
        await _cancelSafely('habit popup:$habitId', () => popup.cancel(id)) &&
        ok;
    ok = await _cancelEmail(id, 'habit:$habitId') && ok;
    return ok;
  }

  Future<bool> _scheduleAnniversaryPushFallback(Anniversary item) async {
    try {
      await notif.scheduleAnniversary(
        annId: item.id,
        title: item.title,
        whenDate: item.nextOccurrence,
        daysBefore: item.remindDaysBefore,
        hour: item.remindHour,
        minute: item.remindMinute,
      );
      return true;
    } on NotificationPermissionDeniedException catch (fallbackError) {
      debugPrint(
        '[ReminderScheduler] anniversary fallback notification permission denied for ${item.id}: $fallbackError',
      );
      return false;
    } catch (fallbackError, st) {
      debugPrint(
        '[ReminderScheduler] anniversary fallback notification dispatch failed for ${item.id}: $fallbackError\n$st',
      );
      return false;
    }
  }

  /// 按最新的纪念日 [items] 幂等地重新同步提醒。
  ///
  /// 纪念日提醒按 `reminderKind` 路由到通知、弹出框、闹钟或关闭；闹钟权限
  /// 不足时自动降级为 push。
  Future<void> syncAnniversaries(Iterable<Anniversary> items) async {
    final snapshot = items.toList(growable: false);
    await _runSerialized(() => _syncAnniversariesLocked(snapshot));
  }

  Future<void> _syncAnniversariesLocked(Iterable<Anniversary> items) async {
    final wanted = <String, Anniversary>{};
    for (final a in items) {
      if (!a.remind) {
        await _cancelAnniversary(a.id);
        await registry.removeObject('anniversary', a.id);
        continue;
      }
      final nextDate = a.nextOccurrence;
      if (nextDate.isBefore(DateTime.now().subtract(const Duration(days: 1)))) {
        await _cancelAnniversary(a.id);
        await registry.removeObject('anniversary', a.id);
        continue;
      }
      if (a.reminderKind == ReminderKind.off) {
        await _cancelAnniversary(a.id);
        await registry.removeObject('anniversary', a.id);
        continue;
      }
      wanted[a.id] = a;
    }
    final scopes = <String, String>{};
    for (final a in wanted.values) {
      final remindAt = _anniversaryReminderAt(a);
      if (!remindAt.isAfter(DateTime.now())) continue;
      scopes[a.id] = _anniversaryScope(a, remindAt);
    }
    final blockedAnniversaryIdsFromRegistry = await _sweepSingleRegistry(
      objectType: 'anniversary',
      wantedIdsByObject: {
        for (final a in wanted.values) a.id: _anniversaryRegistryIds(a),
      },
    );
    wanted.removeWhere(
      (id, _) => blockedAnniversaryIdsFromRegistry.contains(id),
    );
    scopes.removeWhere(
      (id, _) => blockedAnniversaryIdsFromRegistry.contains(id),
    );

    final blockedAnniversaryIds = <String>{};
    for (final id in _scheduledAnniversaryScopes.keys.toList()) {
      final nextScope = scopes[id];
      if (nextScope == null || _scheduledAnniversaryScopes[id] != nextScope) {
        final cancelled = await _cancelAnniversary(id);
        if (cancelled) {
          _scheduledAnniversaryScopes.remove(id);
          await registry.removeObject('anniversary', id);
        } else {
          blockedAnniversaryIds.add(id);
        }
      }
    }

    for (final a in wanted.values) {
      if (blockedAnniversaryIds.contains(a.id)) continue;
      if (!_scheduledAnniversaryScopes.containsKey(a.id)) {
        final swept = await _cancelAnniversary(a.id);
        if (!swept) continue;
      }
      final remindAt = _anniversaryReminderAt(a);
      if (!remindAt.isAfter(DateTime.now())) {
        continue;
      }
      final scope = scopes[a.id]!;
      if (_scheduledAnniversaryScopes[a.id] == scope) {
        if (await _anniversaryStillPending(a)) {
          await registry.replaceObject(
            'anniversary',
            a.id,
            _anniversaryRegistryIds(a),
          );
          continue;
        }
        final cancelled = await _cancelAnniversary(a.id);
        if (!cancelled) continue;
        _scheduledAnniversaryScopes.remove(a.id);
        await registry.removeObject('anniversary', a.id);
      }

      final scheduled = await _dispatchAnniversary(a, remindAt);
      if (scheduled) {
        _scheduledAnniversaryScopes[a.id] = scope;
        await registry.replaceObject(
          'anniversary',
          a.id,
          _anniversaryRegistryIds(a),
        );
      }
    }
  }

  /// 按最新的倒数日 [items] 幂等地同步到期提醒。
  Future<void> syncCountdowns(Iterable<CountdownItem> items) async {
    final snapshot = items.toList(growable: false);
    await _runSerialized(() => _syncCountdownsLocked(snapshot));
  }

  Future<void> _syncCountdownsLocked(Iterable<CountdownItem> items) async {
    final now = DateTime.now();
    final wanted = <String, CountdownItem>{};
    final scopes = <String, String>{};
    for (final item in items) {
      if (!item.remind || item.reminderKind == ReminderKind.off) {
        await _cancelCountdown(item.id);
        await registry.removeObject('countdown', item.id);
        continue;
      }
      final when = _countdownReminderAt(item);
      if (!when.isAfter(now)) {
        await _cancelCountdown(item.id);
        await registry.removeObject('countdown', item.id);
        continue;
      }
      wanted[item.id] = item;
      scopes[item.id] = _countdownScope(item, when);
    }
    final blockedCountdownIdsFromRegistry = await _sweepSingleRegistry(
      objectType: 'countdown',
      wantedIdsByObject: {
        for (final item in wanted.values) item.id: _countdownRegistryIds(item),
      },
    );
    wanted.removeWhere((id, _) => blockedCountdownIdsFromRegistry.contains(id));
    scopes.removeWhere((id, _) => blockedCountdownIdsFromRegistry.contains(id));

    final blockedCountdownIds = <String>{};
    for (final id in _scheduledCountdownScopes.keys.toList()) {
      final nextScope = scopes[id];
      if (nextScope == null || _scheduledCountdownScopes[id] != nextScope) {
        final cancelled = await _cancelCountdown(id);
        if (cancelled) {
          _scheduledCountdownScopes.remove(id);
          await registry.removeObject('countdown', id);
        } else {
          blockedCountdownIds.add(id);
        }
      }
    }

    for (final item in wanted.values) {
      if (blockedCountdownIds.contains(item.id)) continue;
      if (!_scheduledCountdownScopes.containsKey(item.id)) {
        final swept = await _cancelCountdown(item.id);
        if (!swept) continue;
      }
      final scope = scopes[item.id]!;
      if (_scheduledCountdownScopes[item.id] == scope) {
        if (await _countdownStillPending(item)) {
          await registry.replaceObject(
            'countdown',
            item.id,
            _countdownRegistryIds(item),
          );
          continue;
        }
        final cancelled = await _cancelCountdown(item.id);
        if (!cancelled) continue;
        _scheduledCountdownScopes.remove(item.id);
        await registry.removeObject('countdown', item.id);
      }
      final when = _countdownReminderAt(item);
      final scheduled = await _dispatch(
        kind: item.reminderKind,
        payload: _DispatchPayload(
          id: _idFor('countdown:${item.id}:due'),
          title: '🔔 倒数日提醒',
          body:
              '${item.title} · ${item.daysRemaining >= 0 ? '还有 ${item.daysRemaining} 天' : '已过 ${-item.daysRemaining} 天'}',
          when: when,
          payload: 'duoyi://countdown/${item.id}',
          fullScreen: item.reminderKind == ReminderKind.alarm,
        ),
      );
      if (scheduled) {
        _scheduledCountdownScopes[item.id] = scope;
        await registry.replaceObject(
          'countdown',
          item.id,
          _countdownRegistryIds(item),
        );
      }
    }
  }

  /// 按最新的 [goals] 幂等地重新同步目标提醒（支持多 rule）。
  Future<void> syncGoals(Iterable<GoalItem> goals) async {
    final snapshot = goals.toList(growable: false);
    await _runSerialized(() => _syncGoalsLocked(snapshot));
  }

  Future<void> _syncGoalsLocked(Iterable<GoalItem> goals) async {
    final wanted = <String, Map<String, _ResolvedRule>>{};
    for (final g in goals) {
      if (g.status != GoalStatus.active) {
        await _cancelCurrentGoalPlan(g);
        continue;
      }
      final resolved = _resolveGoalRules(g);
      if (resolved.isEmpty) {
        await _cancelCurrentGoalPlan(g);
        continue;
      }
      wanted[g.id] = {for (final rule in resolved) rule.ruleId: rule};
    }
    final blocked = await _sweepRuleRegistry(
      objectType: 'goal',
      wanted: wanted,
    );
    wanted.removeWhere((objectId, _) => blocked.contains(objectId));
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
    final todoSnapshot = todos.toList(growable: false);
    final habitSnapshot = habits.toList(growable: false);
    final anniversarySnapshot = annis.toList(growable: false);
    final goalSnapshot = goals.toList(growable: false);
    final countdownSnapshot = countdowns.toList(growable: false);
    await _runSerialized(
      () => _resyncAllLocked(
        todos: todoSnapshot,
        habits: habitSnapshot,
        annis: anniversarySnapshot,
        goals: goalSnapshot,
        countdowns: countdownSnapshot,
      ),
    );
  }

  Future<void> _resyncAllLocked({
    required Iterable<TodoItem> todos,
    required Iterable<Habit> habits,
    required Iterable<Anniversary> annis,
    required Iterable<GoalItem> goals,
    required Iterable<CountdownItem> countdowns,
  }) async {
    for (final id in _scheduledTodoRules.keys.toList()) {
      final rulesCancelled = await _cancelRuleObjects(
        'todo',
        id,
        _scheduledTodoRules[id]!.keys,
      );
      final legacyCancelled = await _cancelTodoLegacy(id);
      if (rulesCancelled && legacyCancelled) {
        _scheduledTodoRules.remove(id);
        await registry.removeObject('todo', id);
      }
    }
    for (final id in _scheduledGoalRules.keys.toList()) {
      final rulesCancelled = await _cancelRuleObjects(
        'goal',
        id,
        _scheduledGoalRules[id]!.keys,
      );
      final legacyCancelled = await _cancelGoalLegacy(id);
      if (rulesCancelled && legacyCancelled) {
        _scheduledGoalRules.remove(id);
        await registry.removeObject('goal', id);
      }
    }
    for (final id in _scheduledHabitScopes.keys.toList()) {
      if (await _cancelHabit(id)) {
        _scheduledHabitScopes.remove(id);
        await registry.removeObject('habit', id);
      }
    }
    for (final id in _scheduledAnniversaryScopes.keys.toList()) {
      if (await _cancelAnniversary(id)) {
        _scheduledAnniversaryScopes.remove(id);
        await registry.removeObject('anniversary', id);
      }
    }
    for (final id in _scheduledCountdownScopes.keys.toList()) {
      if (await _cancelCountdown(id)) {
        _scheduledCountdownScopes.remove(id);
        await registry.removeObject('countdown', id);
      }
    }

    await _syncTodosLocked(todos, allowJustMissedOneShotReminders: false);
    await _syncHabitsLocked(habits);
    await _syncAnniversariesLocked(annis);
    await _syncGoalsLocked(goals);
    await _syncCountdownsLocked(countdowns);
  }

  Future<T> _runSerialized<T>(Future<T> Function() action) {
    final run = _syncQueue.then((_) => action());
    _syncQueue = run.then<void>((_) {}, onError: (_) {});
    return run;
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
      case ReminderKind.popup:
        try {
          await popup.scheduleOnce(
            id: payload.id,
            title: payload.title,
            body: payload.body,
            when: payload.when,
            payload: payload.payload,
          );
          return true;
        } catch (e, st) {
          debugPrint(
            '[ReminderScheduler] popup dispatch failed for ${payload.id}: $e\n$st',
          );
          return false;
        }
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
        } catch (e, st) {
          debugPrint(
            '[ReminderScheduler] push notification dispatch failed for ${payload.id}: $e\n$st',
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
          if (await _alarmQueueAlreadyOwns(
            label: 'once:${payload.id}',
            expected: <int>{payload.id},
          )) {
            return true;
          }
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
          } catch (fallbackError, fallbackStack) {
            debugPrint(
              '[ReminderScheduler] alarm fallback notification dispatch failed for ${payload.id}: $fallbackError\n$fallbackStack',
            );
            return false;
          }
        } on NotificationPermissionDeniedException catch (e) {
          debugPrint(
            '[ReminderScheduler] alarm notification permission denied for ${payload.id}: $e',
          );
          if (await _alarmQueueAlreadyOwns(
            label: 'once:${payload.id}',
            expected: <int>{payload.id},
          )) {
            return true;
          }
          return false;
        } on AlarmQueueHandoffException catch (e) {
          debugPrint(
            '[ReminderScheduler] alarm queue handoff failed for ${payload.id}: $e',
          );
          return false;
        } catch (e, st) {
          debugPrint(
            '[ReminderScheduler] alarm dispatch failed for ${payload.id}: $e\n$st',
          );
          if (await _alarmQueueAlreadyOwns(
            label: 'once:${payload.id}',
            expected: <int>{payload.id},
          )) {
            return true;
          }
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
          } catch (fallbackError, fallbackStack) {
            debugPrint(
              '[ReminderScheduler] alarm fallback notification dispatch failed for ${payload.id}: $fallbackError\n$fallbackStack',
            );
            return false;
          }
        }
      case ReminderKind.email:
        try {
          await email.scheduleOnce(
            id: payload.id,
            title: payload.title,
            body: payload.body,
            when: payload.when,
            payload: payload.payload,
          );
          return true;
        } catch (e, st) {
          debugPrint(
            '[ReminderScheduler] email dispatch failed for ${payload.id}: $e\n$st',
          );
          return false;
        }
      case ReminderKind.off:
        return false;
    }
  }

  Future<bool> _dispatchRepeating(_ResolvedRule rule) async {
    switch (rule.kind) {
      case ReminderKind.popup:
        try {
          await popup.scheduleRepeating(
            id: _idFor(rule.key),
            title: rule.title,
            body: rule.body,
            hour: rule.hour!,
            minute: rule.minute!,
            weekdays: rule.weekdays.isEmpty ? null : rule.weekdays,
            payload: rule.payload,
          );
          return true;
        } catch (e, st) {
          debugPrint(
            '[ReminderScheduler] repeating popup dispatch failed for ${rule.key}: $e\n$st',
          );
          return false;
        }
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
          if (await _alarmQueueAlreadyOwns(
            label: rule.key,
            expected: _expectedPendingIdsForRule(rule),
            acceptedExpectedSets: _acceptedPendingIdSetsForRule(rule),
          )) {
            return true;
          }
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
          } catch (fallbackError, fallbackStack) {
            debugPrint(
              '[ReminderScheduler] repeating alarm fallback dispatch failed for ${rule.key}: $fallbackError\n$fallbackStack',
            );
            return false;
          }
        } on NotificationPermissionDeniedException catch (e) {
          debugPrint(
            '[ReminderScheduler] alarm notification permission denied for ${rule.key}: $e',
          );
          if (await _alarmQueueAlreadyOwns(
            label: rule.key,
            expected: _expectedPendingIdsForRule(rule),
            acceptedExpectedSets: _acceptedPendingIdSetsForRule(rule),
          )) {
            return true;
          }
          return false;
        } on AlarmQueueHandoffException catch (e) {
          debugPrint(
            '[ReminderScheduler] repeating alarm queue handoff failed for ${rule.key}: $e',
          );
          return false;
        } catch (e, st) {
          debugPrint(
            '[ReminderScheduler] repeating alarm dispatch failed for ${rule.key}: $e\n$st',
          );
          final id = _idFor(rule.key);
          if (await _alarmQueueAlreadyOwns(
            label: rule.key,
            expected: _expectedPendingIdsForRule(rule),
            acceptedExpectedSets: _acceptedPendingIdSetsForRule(rule),
          )) {
            return true;
          }
          try {
            await notif.scheduleDaily(
              id: id,
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
          } catch (fallbackError, fallbackStack) {
            debugPrint(
              '[ReminderScheduler] repeating alarm fallback dispatch failed for ${rule.key}: $fallbackError\n$fallbackStack',
            );
            return false;
          }
        }
      case ReminderKind.email:
        try {
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
        } catch (e, st) {
          debugPrint(
            '[ReminderScheduler] repeating email dispatch failed for ${rule.key}: $e\n$st',
          );
          return false;
        }
      case ReminderKind.off:
        return false;
    }
  }

  // -------------------------------------------------------------------------
  // 内部：取消
  // -------------------------------------------------------------------------

  Future<bool> _cancelTodo(String todoId) async {
    // 双通道清理：即便本地记录的是 push，用户从 alarm 切过来时也能扫到尾巴。
    var ok = true;
    ok =
        await _cancelSafely(
          'todo notification legacy:$todoId',
          () => notif.cancelTodoReminder(todoId),
        ) &&
        ok;
    ok =
        await _cancelSafely(
          'todo alarm legacy:$todoId',
          () => alarm.cancel(_idFor('todo_$todoId')),
        ) &&
        ok;
    return ok;
  }

  Future<bool> _cancelGoal(String goalId) async {
    final id = _idFor('goal_$goalId');
    var ok = true;
    ok =
        await _cancelSafely(
          'goal notification:$goalId',
          () => notif.cancel(id),
        ) &&
        ok;
    ok =
        await _cancelSafely('goal alarm:$goalId', () => alarm.cancel(id)) && ok;
    return ok;
  }

  Future<bool> _cancelTodoLegacy(String todoId) => _cancelTodo(todoId);

  Future<bool> _cancelGoalLegacy(String goalId) => _cancelGoal(goalId);

  Future<bool> _cancelAnniversary(String annId) async {
    var ok = true;
    ok =
        await _cancelSafely(
          'anniversary notification:$annId',
          () => notif.cancelAnniversary(annId),
        ) &&
        ok;
    ok =
        await _cancelSafely(
          'anniversary alarm:$annId',
          () => alarm.cancel(_idFor('anni_alarm_$annId')),
        ) &&
        ok;
    ok =
        await _cancelSafely(
          'anniversary popup:$annId',
          () => popup.cancel(_idFor('anni_$annId')),
        ) &&
        ok;
    ok = await _cancelEmail(_idFor('anni_$annId'), 'anniversary:$annId') && ok;
    return ok;
  }

  Future<bool> _cancelCountdown(String countdownId) async {
    final id = _idFor('countdown:$countdownId:due');
    var ok = true;
    ok =
        await _cancelSafely(
          'countdown notification:$countdownId',
          () => notif.cancel(id),
        ) &&
        ok;
    ok =
        await _cancelSafely(
          'countdown alarm:$countdownId',
          () => alarm.cancel(id),
        ) &&
        ok;
    ok =
        await _cancelSafely(
          'countdown popup:$countdownId',
          () => popup.cancel(id),
        ) &&
        ok;
    ok = await _cancelEmail(id, 'countdown:$countdownId') && ok;
    return ok;
  }

  Future<bool> _cancelRuleObjects(
    String objectType,
    String objectId,
    Iterable<String> ruleIds,
  ) async {
    var ok = true;
    for (final ruleId in ruleIds) {
      ok = await _cancelRule(objectType, objectId, ruleId) && ok;
    }
    return ok;
  }

  Future<Set<String>> _sweepRuleRegistry({
    required String objectType,
    required Map<String, Map<String, _ResolvedRule>> wanted,
  }) async {
    final persisted = await registry.idsByObject(objectType);
    final blocked = <String>{};
    for (final entry in persisted.entries) {
      final objectId = entry.key;
      final wantedRules = wanted[objectId] ?? const <String, _ResolvedRule>{};
      final wantedIds = {
        for (final rule in wantedRules.values) ..._registryIdsForRule(rule),
      };
      final staleIds = entry.value.difference(wantedIds);
      if (staleIds.isEmpty) continue;
      final cancelled = await _cancelIds(objectType, objectId, staleIds);
      if (cancelled) {
        if (wantedIds.isEmpty) {
          await registry.removeObject(objectType, objectId);
        } else {
          await registry.replaceObject(objectType, objectId, wantedIds);
        }
      } else {
        blocked.add(objectId);
      }
    }
    return blocked;
  }

  Future<Set<String>> _sweepSingleRegistry({
    required String objectType,
    required Map<String, Set<int>> wantedIdsByObject,
  }) async {
    final persisted = await registry.idsByObject(objectType);
    final blocked = <String>{};
    for (final entry in persisted.entries) {
      final objectId = entry.key;
      final wantedIds = wantedIdsByObject[objectId] ?? const <int>{};
      final staleIds = entry.value.difference(wantedIds);
      if (staleIds.isEmpty) continue;
      final cancelled = await _cancelIds(objectType, objectId, staleIds);
      if (cancelled) {
        if (wantedIds.isEmpty) {
          await registry.removeObject(objectType, objectId);
        } else {
          await registry.replaceObject(objectType, objectId, wantedIds);
        }
      } else {
        blocked.add(objectId);
      }
    }
    return blocked;
  }

  Future<bool> _cancelCurrentTodoPlan(TodoItem todo) async {
    final plan = _effectiveTodoPlan(todo);
    var ok = await _cancelTodoLegacy(todo.id);
    if (plan.rules.isNotEmpty) {
      ok =
          await _cancelRuleObjects(
            'todo',
            todo.id,
            plan.rules.map((rule) => rule.id),
          ) &&
          ok;
    }
    if (ok) await registry.removeObject('todo', todo.id);
    return ok;
  }

  Future<bool> _cancelCurrentGoalPlan(GoalItem goal) async {
    final plan = goal.reminderPlan.enabled && goal.reminderPlan.rules.isNotEmpty
        ? goal.reminderPlan
        : goal.reminder.enabled
        ? ReminderPlan.fromLegacy(goal.reminder)
        : const ReminderPlan.disabled();
    var ok = await _cancelGoalLegacy(goal.id);
    if (plan.rules.isNotEmpty) {
      ok =
          await _cancelRuleObjects(
            'goal',
            goal.id,
            plan.rules.map((rule) => rule.id),
          ) &&
          ok;
    }
    if (ok) await registry.removeObject('goal', goal.id);
    return ok;
  }

  Future<bool> _cancelIds(
    String objectType,
    String objectId,
    Iterable<int> ids,
  ) async {
    var ok = true;
    for (final id in ids.where((id) => id != 0).toSet()) {
      ok =
          await _cancelSafely(
            '$objectType notification registry:$objectId ($id)',
            () => notif.cancel(id),
          ) &&
          ok;
      ok =
          await _cancelSafely(
            '$objectType alarm registry:$objectId ($id)',
            () => alarm.cancel(id),
          ) &&
          ok;
      ok =
          await _cancelSafely(
            '$objectType popup registry:$objectId ($id)',
            () => popup.cancel(id),
          ) &&
          ok;
      ok = await _cancelEmail(id, '$objectType:$objectId registry') && ok;
    }
    return ok;
  }

  Future<bool> _cancelRule(
    String objectType,
    String objectId,
    String ruleId,
  ) async {
    final intId = _idFor('$objectType:$objectId:$ruleId');
    var ok = true;
    ok =
        await _cancelSafely(
          '$objectType notification:$objectId:$ruleId',
          () => notif.cancel(intId),
        ) &&
        ok;
    ok =
        await _cancelSafely(
          '$objectType alarm:$objectId:$ruleId',
          () => alarm.cancel(intId),
        ) &&
        ok;
    ok = await _cancelEmail(intId, '$objectType:$objectId:$ruleId') && ok;
    ok =
        await _cancelSafely(
          '$objectType popup:$objectId:$ruleId',
          () => popup.cancel(intId),
        ) &&
        ok;
    return ok;
  }

  Future<bool> _cancelEmail(int id, String label) async {
    return _cancelSafely('email:$label ($id)', () => email.cancel(id));
  }

  Future<bool> _cancelSafely(
    String label,
    Future<void> Function() cancel,
  ) async {
    try {
      await cancel();
      return true;
    } catch (e, st) {
      debugPrint('[ReminderScheduler] cancel failed for $label: $e\n$st');
      return false;
    }
  }

  Future<void> _syncRuleObjects({
    required String objectType,
    required Map<String, Map<String, _ResolvedRule>> wanted,
    required Map<String, Map<String, _ScheduledRule>> scheduled,
    required Future<bool> Function(String objectId) cancelLegacy,
  }) async {
    final nextScheduled = <String, Map<String, _ScheduledRule>>{};

    for (final objectId in scheduled.keys.toList()) {
      final priorRules = scheduled[objectId] ?? const {};
      final nextRules = wanted[objectId];
      if (nextRules == null) {
        final rulesCancelled = await _cancelRuleObjects(
          objectType,
          objectId,
          priorRules.keys,
        );
        final legacyCancelled = await cancelLegacy(objectId);
        if (!rulesCancelled || !legacyCancelled) {
          nextScheduled[objectId] = Map<String, _ScheduledRule>.from(
            priorRules,
          );
          await registry.replaceObject(
            objectType,
            objectId,
            _registryIdsForScheduledRules(objectType, objectId, priorRules),
          );
        } else {
          await registry.removeObject(objectType, objectId);
        }
        continue;
      }

      final kept = <String, _ScheduledRule>{};
      final blockedRuleIds = <String>{};
      for (final priorEntry in priorRules.entries) {
        if (!nextRules.containsKey(priorEntry.key)) {
          final cancelled = await _cancelRule(
            objectType,
            objectId,
            priorEntry.key,
          );
          if (!cancelled) {
            kept[priorEntry.key] = priorEntry.value;
            blockedRuleIds.add(priorEntry.key);
          }
        }
      }

      for (final nextEntry in nextRules.entries) {
        final nextRule = nextEntry.value;
        final prior = priorRules[nextEntry.key];
        final needsCancel =
            prior != null && !_sameScheduledRule(prior, nextRule);
        if (needsCancel) {
          final cancelled = await _cancelRule(
            objectType,
            objectId,
            nextEntry.key,
          );
          if (!cancelled) {
            kept[nextEntry.key] = prior;
            blockedRuleIds.add(nextEntry.key);
          }
        }
      }

      final legacyCancelled = await cancelLegacy(objectId);
      for (final nextRule in nextRules.values) {
        if (blockedRuleIds.contains(nextRule.ruleId)) continue;
        if (!legacyCancelled && !priorRules.containsKey(nextRule.ruleId)) {
          continue;
        }
        final prior = priorRules[nextRule.ruleId];
        if (prior != null && _sameScheduledRule(prior, nextRule)) {
          if (await _scheduledRuleStillPending(nextRule)) {
            kept[nextRule.ruleId] = prior;
            continue;
          }
          final cancelled = await _cancelRule(
            objectType,
            objectId,
            nextRule.ruleId,
          );
          if (!cancelled) {
            kept[nextRule.ruleId] = prior;
            continue;
          }
        }
        final ok = await _dispatchRule(nextRule);
        if (ok) {
          kept[nextRule.ruleId] = _scheduledFromResolved(nextRule);
        } else {
          final prior = priorRules[nextRule.ruleId];
          if (prior != null &&
              _sameScheduledRule(prior, nextRule) &&
              await _scheduledRuleStillPending(nextRule)) {
            kept[nextRule.ruleId] = prior;
          }
        }
      }

      if (kept.isNotEmpty) {
        nextScheduled[objectId] = kept;
        await registry.replaceObject(
          objectType,
          objectId,
          _registryIdsForScheduledRules(objectType, objectId, kept),
        );
      } else {
        await registry.removeObject(objectType, objectId);
      }
    }

    for (final entry in wanted.entries) {
      final objectId = entry.key;
      if (scheduled.containsKey(objectId)) continue;

      final nextRules = entry.value;
      final kept = <String, _ScheduledRule>{};
      final legacyCancelled = await cancelLegacy(objectId);
      if (!legacyCancelled) continue;
      for (final nextRule in nextRules.values) {
        final swept = await _cancelRule(objectType, objectId, nextRule.ruleId);
        if (!swept) continue;
        final ok = await _dispatchRule(nextRule);
        if (ok) {
          kept[nextRule.ruleId] = _scheduledFromResolved(nextRule);
        }
      }
      if (kept.isNotEmpty) {
        nextScheduled[objectId] = kept;
        await registry.replaceObject(
          objectType,
          objectId,
          _registryIdsForScheduledRules(objectType, objectId, kept),
        );
      } else {
        await registry.removeObject(objectType, objectId);
      }
    }

    scheduled
      ..clear()
      ..addAll(nextScheduled);
  }

  bool _sameScheduledRule(_ScheduledRule prior, _ResolvedRule next) {
    return prior.kind == next.kind &&
        prior.mode == next.mode &&
        prior.scope == next.scope &&
        prior.fingerprint == next.fingerprint;
  }

  Future<bool> _scheduledRuleStillPending(_ResolvedRule rule) async {
    return _sinkStillPending(
      label: rule.key,
      kind: rule.kind,
      expected: _expectedPendingIdsForRule(rule),
      acceptedExpectedSets: _acceptedPendingIdSetsForRule(rule),
      stalePeerIds: _registryIdsForRule(rule),
    );
  }

  Future<bool> _habitStillPending(Habit habit) async {
    final plan = _effectiveHabitPlan(habit);
    final rule = plan.primaryRule;
    if (rule == null || !rule.enabled || rule.kind == ReminderKind.off) {
      return true;
    }
    final baseId = _idFor('habit_${habit.id}');
    return _sinkStillPending(
      label: 'habit:${habit.id}',
      kind: rule.kind,
      expected: _expectedRepeatingPendingIds(
        baseId,
        _habitWeekdays(habit, rule),
      ),
      acceptedExpectedSets: _acceptedRepeatingPendingIdSets(
        kind: rule.kind,
        base: baseId,
        weekdays: _habitWeekdays(habit, rule),
      ),
      stalePeerIds: _habitRegistryIds(habit),
    );
  }

  Future<bool> _anniversaryStillPending(Anniversary item) {
    final baseId = switch (item.reminderKind) {
      ReminderKind.alarm => _idFor('anni_alarm_${item.id}'),
      _ => _idFor('anni_${item.id}'),
    };
    return _sinkStillPending(
      label: 'anniversary:${item.id}',
      kind: item.reminderKind,
      expected: <int>{baseId},
      notificationFallbackExpectedSets: item.reminderKind == ReminderKind.alarm
          ? <Set<int>>[
              <int>{_idFor('anni_${item.id}')},
            ]
          : null,
      stalePeerIds: _anniversaryRegistryIds(item),
    );
  }

  Future<bool> _countdownStillPending(CountdownItem item) {
    final baseId = _idFor('countdown:${item.id}:due');
    return _sinkStillPending(
      label: 'countdown:${item.id}',
      kind: item.reminderKind,
      expected: <int>{baseId},
      stalePeerIds: _countdownRegistryIds(item),
    );
  }

  Future<bool> _sinkStillPending({
    required String label,
    required ReminderKind kind,
    required Set<int> expected,
    List<Set<int>>? acceptedExpectedSets,
    List<Set<int>>? notificationFallbackExpectedSets,
    Set<int>? stalePeerIds,
  }) async {
    final sink = switch (kind) {
      ReminderKind.push => notif,
      ReminderKind.alarm => alarm,
      _ => null,
    };
    if (sink is! ReminderPendingSink || expected.isEmpty) {
      return _cancelStalePeerPending(
        label: label,
        ownerKind: kind,
        ids: stalePeerIds ?? expected,
      );
    }
    try {
      final actual = (await sink.pendingIds()).toSet();
      final acceptedSets = acceptedExpectedSets ?? <Set<int>>[expected];
      final pendingSatisfied = acceptedSets.any(
        (ids) => ids.isNotEmpty && actual.containsAll(ids),
      );
      if (pendingSatisfied) {
        final staleCleaned = await _cancelStalePeerPending(
          label: label,
          ownerKind: kind,
          ids: stalePeerIds ?? expected,
        );
        return staleCleaned;
      }
      if (kind == ReminderKind.alarm &&
          await _notificationFallbackStillPendingForAlarm(
            label: label,
            acceptedExpectedSets:
                notificationFallbackExpectedSets ?? acceptedSets,
            stalePeerIds: stalePeerIds ?? expected,
          )) {
        return true;
      }
      final missing = expected.difference(actual);
      debugPrint(
        '[ReminderScheduler] pending queue missing for $label: '
        '${missing.join(',')}',
      );
      return false;
    } catch (e, st) {
      debugPrint(
        '[ReminderScheduler] pending probe failed for $label: $e\n$st',
      );
      return false;
    }
  }

  Future<bool> _notificationFallbackStillPendingForAlarm({
    required String label,
    required List<Set<int>> acceptedExpectedSets,
    required Set<int> stalePeerIds,
  }) async {
    if (notif is! ReminderPendingSink) return false;
    try {
      final actual = (await (notif as ReminderPendingSink).pendingIds())
          .toSet();
      final pendingSatisfied = acceptedExpectedSets.any(
        (ids) => ids.isNotEmpty && actual.containsAll(ids),
      );
      if (!pendingSatisfied) return false;
      debugPrint(
        '[ReminderScheduler] notification fallback queue owns alarm reminder '
        'for $label; keep fallback to avoid duplicate delivery.',
      );
      return await _cancelStalePeerPending(
        label: label,
        ownerKind: ReminderKind.push,
        ids: stalePeerIds,
      );
    } catch (e, st) {
      debugPrint(
        '[ReminderScheduler] notification fallback pending probe failed for '
        '$label; keep prior state to avoid duplicate delivery: $e\n$st',
      );
      return true;
    }
  }

  Future<bool> _alarmQueueAlreadyOwns({
    required String label,
    required Set<int> expected,
    List<Set<int>>? acceptedExpectedSets,
  }) async {
    if (alarm is! ReminderPendingSink || expected.isEmpty) return false;
    try {
      final actual = (await (alarm as ReminderPendingSink).pendingIds())
          .toSet();
      final acceptedSets = acceptedExpectedSets ?? <Set<int>>[expected];
      final owns = acceptedSets.any(
        (ids) => ids.isNotEmpty && actual.containsAll(ids),
      );
      if (owns) {
        debugPrint(
          '[ReminderScheduler] alarm dispatch for $label failed after the '
          'alarm queue was registered; skip notification fallback to avoid duplicate delivery.',
        );
      }
      return owns;
    } catch (e, st) {
      debugPrint(
        '[ReminderScheduler] alarm fallback pending probe failed for $label; skip notification fallback to avoid duplicate delivery: $e\n$st',
      );
      return true;
    }
  }

  Future<bool> _cancelStalePeerPending({
    required String label,
    required ReminderKind ownerKind,
    required Set<int> ids,
  }) async {
    if (ids.isEmpty) return true;
    var ok = true;

    Future<void> cleanupPeer({
      required ReminderPendingSink pending,
      required Future<void> Function(int id) cancel,
      required String staleLabel,
    }) async {
      Set<int> staleIds;
      try {
        staleIds = (await pending.pendingIds()).toSet().intersection(ids);
      } catch (e, st) {
        debugPrint(
          '[ReminderScheduler] stale $staleLabel pending probe failed for '
          '$label: $e\n$st',
        );
        ok = false;
        return;
      }
      for (final id in staleIds) {
        ok =
            await _cancelSafely(
              '$label stale $staleLabel owner:$id',
              () => cancel(id),
            ) &&
            ok;
      }
      if (staleIds.isNotEmpty && !ok) {
        debugPrint(
          '[ReminderScheduler] stale $staleLabel owner cleanup incomplete for '
          '$label; keep current owner without re-registering to avoid duplicates.',
        );
      }
    }

    switch (ownerKind) {
      case ReminderKind.push:
        if (alarm is ReminderPendingSink) {
          await cleanupPeer(
            pending: alarm as ReminderPendingSink,
            cancel: alarm.cancel,
            staleLabel: 'alarm',
          );
        }
        break;
      case ReminderKind.alarm:
        if (notif is ReminderPendingSink) {
          await cleanupPeer(
            pending: notif as ReminderPendingSink,
            cancel: notif.cancel,
            staleLabel: 'notification',
          );
        }
        break;
      case ReminderKind.popup:
        if (notif is ReminderPendingSink) {
          await cleanupPeer(
            pending: notif as ReminderPendingSink,
            cancel: notif.cancel,
            staleLabel: 'notification',
          );
        }
        if (alarm is ReminderPendingSink) {
          await cleanupPeer(
            pending: alarm as ReminderPendingSink,
            cancel: alarm.cancel,
            staleLabel: 'alarm',
          );
        }
        break;
      case ReminderKind.email:
      case ReminderKind.off:
        return true;
    }
    return ok;
  }

  Set<int> _expectedRepeatingPendingIds(int base, List<int> weekdays) {
    if (weekdays.isEmpty) return <int>{base};
    return {for (final weekday in weekdays) _subId(base, weekday)};
  }

  Set<int> _expectedPendingIdsForRule(_ResolvedRule rule) {
    final base = _idFor(rule.key);
    if (rule.mode == _DispatchMode.once || rule.weekdays.isEmpty) {
      return <int>{base};
    }
    return {for (final weekday in rule.weekdays) _subId(base, weekday)};
  }

  List<Set<int>> _acceptedPendingIdSetsForRule(_ResolvedRule rule) {
    final base = _idFor(rule.key);
    if (rule.mode == _DispatchMode.once || rule.weekdays.isEmpty) {
      return <Set<int>>[
        <int>{base},
      ];
    }
    return _acceptedRepeatingPendingIdSets(
      kind: rule.kind,
      base: base,
      weekdays: rule.weekdays,
    );
  }

  List<Set<int>> _acceptedRepeatingPendingIdSets({
    required ReminderKind kind,
    required int base,
    required List<int> weekdays,
  }) {
    final expected = _expectedRepeatingPendingIds(base, weekdays);
    if (kind != ReminderKind.alarm || weekdays.isEmpty) {
      return <Set<int>>[expected];
    }
    return <Set<int>>[
      <int>{base},
      expected,
    ];
  }

  Set<int> _registryIdsForRule(_ResolvedRule rule) {
    final base = _idFor(rule.key);
    if (rule.mode == _DispatchMode.once || rule.weekdays.isEmpty) {
      return <int>{base};
    }
    return <int>{
      base,
      for (final weekday in rule.weekdays) _subId(base, weekday),
      for (final weekday in rule.weekdays) _legacySubId(base, weekday),
    };
  }

  Set<int> _registryIdsForScheduledRules(
    String objectType,
    String objectId,
    Map<String, _ScheduledRule> rules,
  ) {
    return {
      for (final entry in rules.entries)
        ..._registryIdsForScheduledRule(
          objectType,
          objectId,
          entry.key,
          entry.value,
        ),
    };
  }

  Set<int> _registryIdsForScheduledRule(
    String objectType,
    String objectId,
    String ruleId,
    _ScheduledRule rule,
  ) {
    final base = _idFor('$objectType:$objectId:$ruleId');
    if (rule.mode == _DispatchMode.once) return <int>{base};
    final weekdays = _weekdaysFromScope(rule.scope);
    if (weekdays.isEmpty) return <int>{base};
    return <int>{
      base,
      for (final weekday in weekdays) _subId(base, weekday),
      for (final weekday in weekdays) _legacySubId(base, weekday),
    };
  }

  List<int> _weekdaysFromScope(String scope) {
    if (!scope.startsWith('weekly:')) return const <int>[];
    final rawDays = scope.substring('weekly:'.length).split(',');
    final result = <int>{};
    for (final raw in rawDays) {
      final day = int.tryParse(raw);
      if (day != null && day >= 1 && day <= 7) result.add(day);
    }
    return result.toList()..sort();
  }

  Set<int> _habitRegistryIds(Habit habit) {
    final plan = _effectiveHabitPlan(habit);
    final rule = plan.primaryRule;
    if (rule == null || !rule.enabled || rule.kind == ReminderKind.off) {
      return const <int>{};
    }
    final base = _idFor('habit_${habit.id}');
    final weekdays = _habitWeekdays(habit, rule);
    if (weekdays.isEmpty) return <int>{base};
    return <int>{
      base,
      for (final weekday in weekdays) _subId(base, weekday),
      for (final weekday in weekdays) _legacySubId(base, weekday),
    };
  }

  Set<int> _anniversaryRegistryIds(Anniversary item) {
    return <int>{_idFor('anni_${item.id}'), _idFor('anni_alarm_${item.id}')};
  }

  Set<int> _countdownRegistryIds(CountdownItem item) {
    return <int>{_idFor('countdown:${item.id}:due')};
  }

  _ScheduledRule _scheduledFromResolved(_ResolvedRule rule) {
    return _ScheduledRule(
      kind: rule.kind,
      mode: rule.mode,
      scope: rule.scope,
      fingerprint: rule.fingerprint,
    );
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

  // -------------------------------------------------------------------------
  // 内部：决定什么时候、以什么通道派发
  // -------------------------------------------------------------------------

  List<_ResolvedRule> _resolveTodoRules(
    TodoItem t, {
    required bool allowJustMissedOneShotReminders,
  }) {
    final plan = _effectiveTodoPlan(t);
    if (!plan.enabled || plan.rules.isEmpty) return const <_ResolvedRule>[];
    final now = DateTime.now();
    final resolved = <_ResolvedRule>[];
    for (final rule in plan.rules) {
      if (!rule.enabled || rule.kind == ReminderKind.off) continue;
      final next = _resolveTodoRule(
        t,
        rule,
        now,
        allowJustMissedOneShotReminders: allowJustMissedOneShotReminders,
      );
      if (next != null) resolved.add(next);
    }
    return _dedupeResolvedRules(resolved);
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

  _ResolvedRule? _resolveTodoRule(
    TodoItem t,
    ReminderRule rule,
    DateTime now, {
    required bool allowJustMissedOneShotReminders,
  }) {
    switch (rule.type) {
      case ReminderRuleType.absolute:
        final payload = _todoPayload(t.id, rule.kind);
        final anchor = t.dueDate ?? t.reminderAt;
        if (anchor == null) return null;
        final hour = rule.hour ?? anchor.hour;
        final minute = rule.minute ?? anchor.minute;
        if (!_validTime(hour, minute)) return null;
        final when = _dateAtTime(anchor, hour, minute);
        final scheduledWhen = _resolveOneShotReminderTime(
          when,
          now,
          allowJustMissed: allowJustMissedOneShotReminders,
        );
        if (scheduledWhen == null) return null;
        return _buildOnceRule(
          objectType: 'todo',
          objectId: t.id,
          rule: rule,
          title: _titleFor('todo', rule.type, rule.kind),
          body: t.title,
          payload: payload,
          when: scheduledWhen,
        );
      case ReminderRuleType.relativeToDue:
        final payload = _todoPayload(t.id, rule.kind);
        final anchor = t.dueDate ?? t.reminderAt;
        if (anchor == null) return null;
        final hour = rule.hour ?? anchor.hour;
        final minute = rule.minute ?? anchor.minute;
        if (!_validTime(hour, minute)) return null;
        final base = _dateAtTime(anchor, hour, minute);
        final when = base.add(Duration(minutes: rule.offsetMinutes ?? 0));
        final scheduledWhen = _resolveOneShotReminderTime(
          when,
          now,
          allowJustMissed: allowJustMissedOneShotReminders,
        );
        if (scheduledWhen == null) return null;
        return _buildOnceRule(
          objectType: 'todo',
          objectId: t.id,
          rule: rule,
          title: _titleFor('todo', rule.type, rule.kind),
          body: t.title,
          payload: payload,
          when: scheduledWhen,
        );
      case ReminderRuleType.dailyTime:
        final payload = _todoPayload(t.id, rule.kind);
        if (!_validTime(rule.hour, rule.minute)) return null;
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
        if (!_validTime(rule.hour, rule.minute) || rule.weekdays.isEmpty) {
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
      if (!rule.enabled || rule.kind == ReminderKind.off) continue;
      final next = _resolveGoalRule(g, rule, now);
      if (next != null) resolved.add(next);
    }
    return _dedupeResolvedRules(resolved);
  }

  List<_ResolvedRule> _dedupeResolvedRules(List<_ResolvedRule> rules) {
    if (rules.length < 2) return rules;
    final selectedOnceRuleKeys = <String>{};
    final selectedWeekdaysByRuleKey = <String, Set<int>>{};
    final selectedByOccurrence = <String, _ResolvedRule>{};
    for (final rule in rules) {
      if (rule.mode == _DispatchMode.repeating) {
        for (final weekday in _logicalDeliveryWeekdays(rule)) {
          final fingerprint = _logicalRepeatingDeliveryFingerprint(
            rule,
            weekday,
          );
          final prior = selectedByOccurrence[fingerprint];
          if (prior == null ||
              _deliveryPriority(rule.kind) > _deliveryPriority(prior.kind)) {
            if (prior != null) {
              selectedWeekdaysByRuleKey[prior.key]?.remove(weekday);
            }
            selectedByOccurrence[fingerprint] = rule;
            selectedWeekdaysByRuleKey
                .putIfAbsent(rule.key, () => <int>{})
                .add(weekday);
          }
        }
        continue;
      }

      final fingerprint = rule.logicalDeliveryFingerprint;
      final prior = selectedByOccurrence[fingerprint];
      if (prior == null ||
          _deliveryPriority(rule.kind) > _deliveryPriority(prior.kind)) {
        if (prior != null) {
          selectedOnceRuleKeys.remove(prior.key);
        }
        selectedByOccurrence[fingerprint] = rule;
        selectedOnceRuleKeys.add(rule.key);
      }
    }

    final result = <_ResolvedRule>[];
    for (final rule in rules) {
      if (rule.mode == _DispatchMode.repeating) {
        final weekdays = selectedWeekdaysByRuleKey[rule.key];
        if (weekdays == null || weekdays.isEmpty) continue;
        final original = _logicalDeliveryWeekdays(rule).toSet();
        if (weekdays.length == original.length &&
            weekdays.containsAll(original)) {
          result.add(rule);
        } else {
          result.add(_copyRepeatingRuleWithWeekdays(rule, weekdays));
        }
      } else if (selectedOnceRuleKeys.contains(rule.key)) {
        result.add(rule);
      }
    }
    return result;
  }

  int _deliveryPriority(ReminderKind kind) {
    return switch (kind) {
      ReminderKind.alarm => 4,
      ReminderKind.push => 3,
      ReminderKind.popup => 2,
      ReminderKind.email => 1,
      ReminderKind.off => 0,
    };
  }

  List<int> _logicalDeliveryWeekdays(_ResolvedRule rule) {
    final weekdays = _normalizedWeekdays(rule.weekdays);
    if (weekdays.isEmpty) return const <int>[1, 2, 3, 4, 5, 6, 7];
    return weekdays;
  }

  String _logicalRepeatingDeliveryFingerprint(_ResolvedRule rule, int weekday) {
    return [
      rule.objectType,
      rule.objectId,
      rule.mode.name,
      rule.body,
      rule.hour?.toString() ?? '-',
      rule.minute?.toString() ?? '-',
      weekday,
    ].join('|');
  }

  _ResolvedRule _copyRepeatingRuleWithWeekdays(
    _ResolvedRule rule,
    Iterable<int> weekdays,
  ) {
    final normalized = _normalizedWeekdays(weekdays.toList());
    final scope = normalized.length == 7
        ? 'daily'
        : 'weekly:${normalized.join(',')}';
    return _ResolvedRule(
      objectType: rule.objectType,
      objectId: rule.objectId,
      ruleId: rule.ruleId,
      kind: rule.kind,
      mode: rule.mode,
      ruleType: normalized.length == 7
          ? ReminderRuleType.dailyTime
          : ReminderRuleType.weeklyTime,
      title: rule.title,
      body: rule.body,
      payload: rule.payload,
      fullScreen: rule.fullScreen,
      vibrate: rule.vibrate,
      snoozeMinutes: rule.snoozeMinutes,
      repeatCount: rule.repeatCount,
      hour: rule.hour,
      minute: rule.minute,
      weekdays: normalized.length == 7 ? const <int>[] : normalized,
      scope: scope,
    );
  }

  _ResolvedRule? _resolveGoalRule(GoalItem g, ReminderRule rule, DateTime now) {
    final payload = 'duoyi://goal/${g.id}';
    switch (rule.type) {
      case ReminderRuleType.absolute:
        final anchorDate = _goalAnchorDate(g, now);
        final hour = rule.hour ?? anchorDate.hour;
        final minute = rule.minute ?? anchorDate.minute;
        if (!_validTime(hour, minute)) return null;
        final when = _dateAtTime(anchorDate, hour, minute);
        if (!when.isAfter(now)) {
          final tomorrow = DateTime(
            now.year,
            now.month,
            now.day,
          ).add(const Duration(days: 1));
          final fallback = _dateAtTime(tomorrow, hour, minute);
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
        final hour = rule.hour ?? anchor.hour;
        final minute = rule.minute ?? anchor.minute;
        if (!_validTime(hour, minute)) return null;
        final base = _dateAtTime(anchor, hour, minute);
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
        if (!_validTime(rule.hour, rule.minute)) return null;
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
        if (!_validTime(rule.hour, rule.minute) || rule.weekdays.isEmpty) {
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
    return '${when.millisecondsSinceEpoch}:${item.title}:${item.remindDaysBefore}:${item.remindHour}:${item.remindMinute}:${item.reminderKind.name}';
  }

  String _habitScope(Habit habit) {
    final plan = _effectiveHabitPlan(habit);
    final rule = plan.primaryRule;
    if (!plan.enabled || rule == null) return 'off';
    final weekdays = _habitWeekdays(habit, rule);
    return [
      habit.name,
      rule.kind.name,
      rule.type.name,
      rule.hour,
      rule.minute,
      rule.fullScreen,
      rule.vibrate,
      rule.snoozeMinutes,
      rule.repeatCount,
      weekdays.join(','),
    ].join('|');
  }

  ReminderPlan _effectiveHabitPlan(Habit habit) {
    if (habit.reminderPlan.enabled && habit.reminderPlan.rules.isNotEmpty) {
      return habit.reminderPlan;
    }
    if (habit.remind &&
        habit.remindHour != null &&
        habit.remindMinute != null) {
      final weekdays = habit.activeWeekdays.map((w) => w + 1).toSet().toList()
        ..sort();
      return ReminderPlan(
        enabled: true,
        rules: [
          ReminderRule(
            id: 'habit-reminder',
            enabled: true,
            type: weekdays.length == 7
                ? ReminderRuleType.dailyTime
                : ReminderRuleType.weeklyTime,
            kind: ReminderKind.alarm,
            hour: habit.remindHour,
            minute: habit.remindMinute,
            weekdays: weekdays.length == 7 ? const <int>[] : weekdays,
            fullScreen: true,
            snoozeMinutes: 5,
          ),
        ],
      );
    }
    return const ReminderPlan.disabled();
  }

  List<int> _habitWeekdays(Habit habit, ReminderRule rule) {
    if (rule.type == ReminderRuleType.weeklyTime && rule.weekdays.isNotEmpty) {
      return _normalizedWeekdays(rule.weekdays);
    }
    if (rule.type == ReminderRuleType.dailyTime) return const <int>[];
    final weekdays =
        habit.activeWeekdays
            .where((w) => w >= 0 && w <= 6)
            .map((w) => w + 1)
            .toSet()
            .toList()
          ..sort();
    return weekdays.length == 7 ? const <int>[] : weekdays;
  }

  String _habitTitle(ReminderKind kind) {
    return switch (kind) {
      ReminderKind.alarm => '⏰ 习惯打卡',
      ReminderKind.popup || ReminderKind.push => '🔔 习惯打卡',
      ReminderKind.email => '✉️ 习惯打卡',
      ReminderKind.off => '🔕 习惯打卡',
    };
  }

  List<int> _normalizedWeekdays(List<int> weekdays) {
    final normalized = <int>{};
    for (final day in weekdays) {
      if (day >= 1 && day <= 7) normalized.add(day);
    }
    final result = normalized.toList()..sort();
    return result;
  }

  bool _validTime(int? hour, int? minute) {
    return hour != null &&
        minute != null &&
        hour >= 0 &&
        hour <= 23 &&
        minute >= 0 &&
        minute <= 59;
  }

  String _titleFor(
    String objectType,
    ReminderRuleType type,
    ReminderKind kind,
  ) {
    final subject = objectType == 'goal' ? '目标' : '待办';
    final prefix = switch (kind) {
      ReminderKind.alarm => '⏰',
      ReminderKind.popup => '🔔',
      ReminderKind.email => '✉️',
      ReminderKind.off => '🔕',
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

  Future<bool> _dispatchAnniversary(Anniversary item, DateTime remindAt) async {
    switch (item.reminderKind) {
      case ReminderKind.push:
        try {
          await notif.scheduleAnniversary(
            annId: item.id,
            title: item.title,
            whenDate: item.nextOccurrence,
            daysBefore: item.remindDaysBefore,
            hour: item.remindHour,
            minute: item.remindMinute,
          );
          return true;
        } on NotificationPermissionDeniedException catch (e) {
          debugPrint(
            '[ReminderScheduler] anniversary push permission denied for ${item.id}: $e',
          );
          return false;
        } catch (e, st) {
          debugPrint(
            '[ReminderScheduler] anniversary push dispatch failed for ${item.id}: $e\n$st',
          );
          return false;
        }
      case ReminderKind.popup:
        try {
          await popup.scheduleOnce(
            id: _idFor('anni_${item.id}'),
            title: '🔔 纪念日提醒',
            body: item.remindDaysBefore == 0
                ? '今天是 ${item.title}'
                : '${item.remindDaysBefore} 天后是 ${item.title}',
            when: remindAt,
            payload: 'duoyi://anniversary/${item.id}',
          );
          return true;
        } catch (e, st) {
          debugPrint(
            '[ReminderScheduler] anniversary popup dispatch failed for ${item.id}: $e\n$st',
          );
          return false;
        }
      case ReminderKind.alarm:
        try {
          await alarm.scheduleFullScreen(
            id: _idFor('anni_alarm_${item.id}'),
            title: '⏰ 纪念日提醒',
            body: item.remindDaysBefore == 0
                ? '今天是 ${item.title}'
                : '${item.remindDaysBefore} 天后是 ${item.title}',
            when: remindAt,
            payload: 'duoyi://anniversary/${item.id}',
          );
          return true;
        } on AlarmPermissionDeniedException catch (e) {
          debugPrint(
            '[ReminderScheduler] anniversary alarm permission denied for ${item.id}: $e',
          );
          final id = _idFor('anni_alarm_${item.id}');
          if (await _alarmQueueAlreadyOwns(
            label: 'anniversary:${item.id}',
            expected: <int>{id},
          )) {
            return true;
          }
          return _scheduleAnniversaryPushFallback(item);
        } on NotificationPermissionDeniedException catch (e) {
          debugPrint(
            '[ReminderScheduler] anniversary notification permission denied for ${item.id}: $e',
          );
          final id = _idFor('anni_alarm_${item.id}');
          if (await _alarmQueueAlreadyOwns(
            label: 'anniversary:${item.id}',
            expected: <int>{id},
          )) {
            return true;
          }
          return false;
        } on AlarmQueueHandoffException catch (e) {
          debugPrint(
            '[ReminderScheduler] anniversary alarm queue handoff failed for ${item.id}: $e',
          );
          return false;
        } catch (e, st) {
          debugPrint(
            '[ReminderScheduler] anniversary alarm dispatch failed for ${item.id}: $e\n$st',
          );
          final id = _idFor('anni_alarm_${item.id}');
          if (await _alarmQueueAlreadyOwns(
            label: 'anniversary:${item.id}',
            expected: <int>{id},
          )) {
            return true;
          }
          return _scheduleAnniversaryPushFallback(item);
        }
      case ReminderKind.email:
        try {
          await email.scheduleOnce(
            id: _idFor('anni_${item.id}'),
            title: '✉️ 纪念日提醒',
            body: item.remindDaysBefore == 0
                ? '今天是 ${item.title}'
                : '${item.remindDaysBefore} 天后是 ${item.title}',
            when: remindAt,
            payload: 'duoyi://anniversary/${item.id}',
          );
          return true;
        } catch (e, st) {
          debugPrint(
            '[ReminderScheduler] anniversary email dispatch failed for ${item.id}: $e\n$st',
          );
          return false;
        }
      case ReminderKind.off:
        return false;
    }
  }

  String? _fallbackPayload(String? payload) {
    if (payload == null) return null;
    final uri = Uri.tryParse(payload);
    if (uri == null) return payload;
    final query = Map<String, String>.from(uri.queryParameters)
      ..remove('confirm')
      ..['fallback'] = 'push';
    return uri.replace(queryParameters: query).toString();
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
    return _avoidReservedNotificationId(h);
  }

  int _avoidReservedNotificationId(int id) {
    var next = id;
    while (_reservedNotificationIds.contains(next)) {
      next = (next + 1) & 0x7fffffff;
    }
    return next;
  }

  static const Set<int> _reservedNotificationIds = <int>{
    880016,
    880017,
    880018,
    880019,
    880020,
    880021,
    880022,
    880023,
    919001,
    919002,
    919003,
    919004,
  };

  DateTime _anniversaryReminderAt(Anniversary item) {
    final next = item.nextOccurrence;
    return DateTime(
      next.year,
      next.month,
      next.day,
      item.remindHour,
      item.remindMinute,
    ).subtract(Duration(days: item.remindDaysBefore));
  }

  String _anniversaryScope(Anniversary item, DateTime when) {
    return [
      item.reminderKind.index,
      item.title,
      item.remindDaysBefore,
      item.remindHour,
      item.remindMinute,
      when.toIso8601String(),
    ].join('|');
  }
}
