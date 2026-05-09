import '../models/anniversary.dart';
import '../models/goal.dart';
import '../models/habit.dart';
import '../models/todo.dart';
import 'alarm_service.dart';
import 'reminder_sinks.dart';

/// 推送 / 闹钟路由分发用的统一载荷。
class _DispatchPayload {
  final int id;
  final String title;
  final String body;
  final DateTime when;
  final String? payload;

  const _DispatchPayload({
    required this.id,
    required this.title,
    required this.body,
    required this.when,
    this.payload,
  });
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

  /// 上一轮已下发的 todo id → 使用的通道；用于精确取消（即便用户改了 kind
  /// 也能清掉旧通道的残留）。
  final Map<String, ReminderKind> _scheduledTodoKinds = {};
  final Set<String> _scheduledHabitIds = {};
  final Set<String> _scheduledAnniIds = {};
  final Map<String, ReminderKind> _scheduledGoalKinds = {};

  /// [notif] 必传；[alarm] 默认取 `AlarmService.instance` 单例，便于测试时
  /// 注入 fake。两者均以 `ReminderNotificationSink` / `ReminderAlarmSink`
  /// 接口表达，便于 Task 14.3 的 PBT 用 Fake 实例注入。
  ReminderScheduler(
    ReminderNotificationSink notif, {
    ReminderAlarmSink? alarm,
  })  : notif = notif,
        alarm = alarm ?? AlarmService.instance;

  // -------------------------------------------------------------------------
  // 公共 API
  // -------------------------------------------------------------------------

  /// 按最新的 [todos] 幂等地重新同步待办提醒。
  ///
  /// 路由规则：
  /// - `t.reminder.enabled && t.reminder.kind == alarm` → `AlarmService`；
  /// - `t.reminder.enabled && t.reminder.kind == push`  → `NotificationService`；
  /// - 仅有遗留 `hasReminder = true`（未写入新 `reminder`）→ 走 push 回退。
  Future<void> syncTodos(Iterable<TodoItem> todos) async {
    final wanted = <String, _ResolvedTodo>{};
    for (final t in todos) {
      if (t.isCompleted) continue;
      final resolved = _resolveTodo(t);
      if (resolved == null) continue;
      wanted[t.id] = resolved;
    }

    // 1) 取消不再需要的：当前不存在或 kind 翻转的旧调度。
    final prior = Map<String, ReminderKind>.from(_scheduledTodoKinds);
    for (final entry in prior.entries) {
      final id = entry.key;
      final next = wanted[id];
      if (next == null || next.kind != entry.value) {
        await _cancelTodo(id);
      }
    }

    // 2) 重新下发。
    _scheduledTodoKinds.clear();
    for (final e in wanted.entries) {
      final id = e.key;
      final r = e.value;
      final intId = _idFor('todo_$id');
      await _dispatch(
        kind: r.kind,
        payload: _DispatchPayload(
          id: intId,
          title: r.title,
          body: r.body,
          when: r.when,
          payload: 'duoyi://tab/todo',
        ),
      );
      _scheduledTodoKinds[id] = r.kind;
    }
  }

  /// 按最新的 [habits] 幂等地重新同步习惯提醒。
  ///
  /// TODO(task-22): 习惯模型当前仍使用遗留的 `remind / remindHour /
  /// remindMinute` 字段，`ReminderKind` 维度暂由 `NotificationService`
  /// 统一以 push 通道承载；后续引入 `ReminderConfig` 后再按 kind 分发。
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

  /// 按最新的纪念日 [items] 幂等地重新同步提醒。
  ///
  /// TODO(task-22): 纪念日模型暂无 `ReminderConfig.kind` 概念，按设计
  /// §2.4 默认走 push；若后续补上 kind 再接入 `_dispatch`。
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

  /// 按最新的 [goals] 幂等地重新同步目标提醒（一次性：下一次触发）。
  ///
  /// 当前按 `reminder.hour / reminder.minute` 直接锚定今日（或次日，如果
  /// 今日对应时刻已过）或 `startDate`；更精细的"下一派发日"逻辑由
  /// Task 22 的 `RecurrenceEngine.nextOccurrence` 介入后替换。
  Future<void> syncGoals(Iterable<GoalItem> goals) async {
    final wanted = <String, _ResolvedGoal>{};
    for (final g in goals) {
      if (g.status != GoalStatus.active) continue;
      final resolved = _resolveGoal(g);
      if (resolved == null) continue;
      wanted[g.id] = resolved;
    }

    // 1) 取消不再需要 / kind 翻转的旧调度。
    final prior = Map<String, ReminderKind>.from(_scheduledGoalKinds);
    for (final entry in prior.entries) {
      final id = entry.key;
      final next = wanted[id];
      if (next == null || next.kind != entry.value) {
        await _cancelGoal(id);
      }
    }

    // 2) 重新下发。
    _scheduledGoalKinds.clear();
    for (final e in wanted.entries) {
      final id = e.key;
      final r = e.value;
      final intId = _idFor('goal_$id');
      await _dispatch(
        kind: r.kind,
        payload: _DispatchPayload(
          id: intId,
          title: r.title,
          body: r.body,
          when: r.when,
          payload: 'duoyi://tab/goal',
        ),
      );
      _scheduledGoalKinds[id] = r.kind;
    }
  }

  /// 时区变化、权限变化、应用冷启动时整轮重放（R4.7）。
  ///
  /// 与 `syncXxx` 不同的是：本方法先无条件地按当前已记录的通道取消所有
  /// 自己管过的 id，再按 provider 最新数据重新下发。调用方（通常是
  /// `main.dart` 的 `AppLifecycle.resumed` hook，Task 14.2）可据此拿到
  /// 与最新时区、权限匹配的调度队列。
  Future<void> resyncAll({
    required Iterable<TodoItem> todos,
    required Iterable<Habit> habits,
    required Iterable<Anniversary> annis,
    required Iterable<GoalItem> goals,
  }) async {
    // 先按已记录的 kind 取消，避免时区漂移后遗留的错位调度。
    for (final id in _scheduledTodoKinds.keys.toList()) {
      await _cancelTodo(id);
    }
    for (final id in _scheduledGoalKinds.keys.toList()) {
      await _cancelGoal(id);
    }
    for (final id in _scheduledHabitIds.toList()) {
      await notif.cancelHabitReminder(id);
    }
    for (final id in _scheduledAnniIds.toList()) {
      await notif.cancelAnniversary(id);
    }
    _scheduledTodoKinds.clear();
    _scheduledGoalKinds.clear();
    _scheduledHabitIds.clear();
    _scheduledAnniIds.clear();

    await syncTodos(todos);
    await syncHabits(habits);
    await syncAnniversaries(annis);
    await syncGoals(goals);
  }

  // -------------------------------------------------------------------------
  // 内部：通道路由
  // -------------------------------------------------------------------------

  /// 按 [kind] 路由到 push 或 alarm。抛错一律向上冒泡（例如
  /// [AlarmPermissionDeniedException]），由调用方捕获后引导用户。
  Future<void> _dispatch({
    required ReminderKind kind,
    required _DispatchPayload payload,
  }) async {
    switch (kind) {
      case ReminderKind.push:
        await notif.scheduleOnce(
          id: payload.id,
          title: payload.title,
          body: payload.body,
          when: payload.when,
          payload: payload.payload,
        );
        return;
      case ReminderKind.alarm:
        await alarm.scheduleFullScreen(
          id: payload.id,
          title: payload.title,
          body: payload.body,
          when: payload.when,
          payload: payload.payload,
        );
        return;
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

  // -------------------------------------------------------------------------
  // 内部：决定什么时候、以什么通道派发
  // -------------------------------------------------------------------------

  _ResolvedTodo? _resolveTodo(TodoItem t) {
    // 优先新 ReminderConfig；否则回退到遗留 hasReminder + reminderAt。
    final r = t.reminder;
    final useNew = r.enabled;
    // ignore: deprecated_member_use_from_same_package
    final useLegacy = !useNew && t.hasReminder;
    if (!useNew && !useLegacy) return null;

    DateTime? when;
    if (useNew) {
      final anchor = t.dueDate ?? t.reminderAt;
      if (anchor == null) return null;
      if (r.hour != null && r.minute != null) {
        when = DateTime(
          anchor.year,
          anchor.month,
          anchor.day,
          r.hour!,
          r.minute!,
        );
      } else {
        when = anchor;
      }
    } else {
      // legacy
      when = t.reminderAt ?? t.dueDate;
    }
    if (when == null) return null;
    if (when.isBefore(DateTime.now())) return null;

    return _ResolvedTodo(
      kind: useNew ? r.kind : ReminderKind.push,
      title: useNew && r.kind == ReminderKind.alarm
          ? '⏰ 待办到期'
          : '📝 待办提醒',
      body: t.title,
      when: when,
    );
  }

  _ResolvedGoal? _resolveGoal(GoalItem g) {
    final r = g.reminder;
    if (!r.enabled) return null;
    if (r.hour == null || r.minute == null) return null;

    final now = DateTime.now();
    final anchorDate = _goalAnchorDate(g, now);
    var when = DateTime(
      anchorDate.year,
      anchorDate.month,
      anchorDate.day,
      r.hour!,
      r.minute!,
    );
    // 锚定日已过：挪到次日同一时刻。
    if (!when.isAfter(now)) {
      final tomorrow = DateTime(now.year, now.month, now.day)
          .add(const Duration(days: 1));
      when = DateTime(
        tomorrow.year,
        tomorrow.month,
        tomorrow.day,
        r.hour!,
        r.minute!,
      );
    }

    return _ResolvedGoal(
      kind: r.kind,
      title: r.kind == ReminderKind.alarm ? '⏰ 目标派发' : '🎯 目标提醒',
      body: g.title,
      when: when,
    );
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

class _ResolvedTodo {
  final ReminderKind kind;
  final String title;
  final String body;
  final DateTime when;

  const _ResolvedTodo({
    required this.kind,
    required this.title,
    required this.body,
    required this.when,
  });
}

class _ResolvedGoal {
  final ReminderKind kind;
  final String title;
  final String body;
  final DateTime when;

  const _ResolvedGoal({
    required this.kind,
    required this.title,
    required this.body,
    required this.when,
  });
}
