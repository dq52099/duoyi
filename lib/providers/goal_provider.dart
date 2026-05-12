import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/domain_event_bus.dart';
import '../core/recommended_goals.dart';
import '../models/goal.dart';
import '../services/reminder_scheduler.dart';
import 'time_audit_provider.dart';

class GoalProvider extends ChangeNotifier {
  static const _key = 'duoyi_goals';
  List<GoalItem> _goals = [];
  TimeAuditProvider? _timeAudit;

  /// 可选的 [ReminderScheduler] 引用，由 `main.dart` 在构造完整对象图后注入。
  ///
  /// 设计上允许 `null`：GoalProvider 的持久化路径**不**强依赖调度器，
  /// 只有在 [onTimezoneChanged] 这种显式 hook 里才会尝试转发给调度器。
  ///
  /// TODO(task-14.1): 当 `ReminderScheduler.syncGoals` 正式落地后，
  /// 把 [onTimezoneChanged] 中的 dynamic 兜底调用替换为直接调用。
  ReminderScheduler? _scheduler;

  /// 注入或解绑调度器；传 `null` 即解绑。
  // ignore: use_setters_to_change_properties
  set scheduler(ReminderScheduler? s) {
    _scheduler = s;
  }

  // ignore: use_setters_to_change_properties
  set timeAudit(TimeAuditProvider? provider) {
    _timeAudit = provider;
  }

  List<GoalItem> get goals {
    final sorted = [..._goals];
    sorted.sort((a, b) {
      // 进行中 > 已完成 > 暂停 > 放弃
      int statusRank(GoalItem g) => switch (g.status) {
        GoalStatus.active => 0,
        GoalStatus.paused => 2,
        GoalStatus.achieved => 1,
        GoalStatus.abandoned => 3,
      };
      final s = statusRank(a).compareTo(statusRank(b));
      if (s != 0) return s;
      return a.sortOrder.compareTo(b.sortOrder);
    });
    return List.unmodifiable(sorted);
  }

  List<GoalItem> get activeGoals =>
      _goals.where((g) => g.status == GoalStatus.active).toList();

  Future<void> loadFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    _goals = raw.map((e) => GoalItem.fromJson(jsonDecode(e))).toList();
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _key,
      _goals.map((e) => jsonEncode(e.toJson())).toList(),
    );
    notifyListeners();
  }

  Future<void> add(GoalItem goal) async {
    _goals.add(goal);
    DomainEventBus.instance.publish(
      DomainEvent(type: DomainEventType.goalCreated, objectId: goal.id),
    );
    await _save();
  }

  /// 把推荐模板实例化为真实 [GoalItem] 并入库。
  ///
  /// 等价于 `add(RecommendedGoalsLibrary.instantiate(r))`，但由 Provider
  /// 统一把控"实例化 + 持久化"流程，避免在 UI 层散落相同的两步调用。
  /// 返回新创建的 [GoalItem]，以便上游 Widget 做"查看 / 回传"之类的后续跳转。
  Future<GoalItem> applyRecommended(RecommendedGoal r) async {
    final goal = RecommendedGoalsLibrary.instantiate(r);
    _goals.add(goal);
    DomainEventBus.instance.publish(
      DomainEvent(type: DomainEventType.goalCreated, objectId: goal.id),
    );
    await _save();
    return goal;
  }

  Future<void> update(GoalItem goal) async {
    final idx = _goals.indexWhere((g) => g.id == goal.id);
    if (idx != -1) {
      final prev = _goals[idx];
      final wasAchieved = prev.status == GoalStatus.achieved;
      goal.updatedAt = DateTime.now();
      _goals[idx] = goal;
      await _save();
      if (!wasAchieved && goal.status == GoalStatus.achieved) {
        DomainEventBus.instance.publish(
          DomainEvent(type: DomainEventType.goalAchieved, objectId: goal.id),
        );
      }
      await _syncTimeEntriesForGoal(prev, goal);
    }
  }

  Future<void> delete(String id) async {
    if (_timeAudit != null) {
      await _timeAudit!.deleteGoalEntries(id);
    }
    _goals.removeWhere((g) => g.id == id);
    await _save();
  }

  Future<void> setStatus(String id, GoalStatus status) async {
    final idx = _goals.indexWhere((g) => g.id == id);
    if (idx != -1) {
      _goals[idx].status = status;
      if (status == GoalStatus.achieved) _goals[idx].progress = 1.0;
      _goals[idx].updatedAt = DateTime.now();
      await _save();
      if (status == GoalStatus.achieved) {
        DomainEventBus.instance.publish(
          DomainEvent(
            type: DomainEventType.goalAchieved,
            objectId: _goals[idx].id,
          ),
        );
      }
    }
  }

  Future<void> toggleMilestone(String goalId, String milestoneId) async {
    final idx = _goals.indexWhere((g) => g.id == goalId);
    if (idx != -1 && _goals[idx].milestones.isNotEmpty) {
      final m = _goals[idx].milestones.firstWhere(
        (x) => x.id == milestoneId,
        orElse: () => _goals[idx].milestones.first,
      );
      final wasCompleted = m.isCompleted;
      m.isCompleted = !m.isCompleted;
      m.completedAt = m.isCompleted ? DateTime.now() : null;
      if (!wasCompleted && m.isCompleted) {
        DomainEventBus.instance.publish(
          DomainEvent(
            type: DomainEventType.goalMilestoneCompleted,
            objectId: m.id,
            metadata: {'goalId': goalId},
          ),
        );
      }
      _goals[idx].updatedAt = DateTime.now();

      // 自动完成目标
      if (_goals[idx].autoProgress &&
          _goals[idx].milestones.isNotEmpty &&
          _goals[idx].milestones.every((x) => x.isCompleted) &&
          _goals[idx].status == GoalStatus.active) {
        _goals[idx].status = GoalStatus.achieved;
        _goals[idx].progress = 1.0;
        DomainEventBus.instance.publish(
          DomainEvent(type: DomainEventType.goalAchieved, objectId: goalId),
        );
      } else if (_goals[idx].status == GoalStatus.achieved &&
          !m.isCompleted &&
          _goals[idx].autoProgress) {
        _goals[idx].status = GoalStatus.active;
      }
      await _save();
      await _syncMilestoneEntry(_goals[idx], m, wasCompleted: wasCompleted);
    }
  }

  Future<void> addMilestone(String goalId, String title) async {
    final idx = _goals.indexWhere((g) => g.id == goalId);
    if (idx != -1) {
      _goals[idx].milestones.add(GoalMilestone(title: title));
      _goals[idx].updatedAt = DateTime.now();
      await _save();
    }
  }

  Future<void> removeMilestone(String goalId, String milestoneId) async {
    final idx = _goals.indexWhere((g) => g.id == goalId);
    if (idx != -1) {
      final milestone = _goals[idx].milestones.firstWhere(
        (m) => m.id == milestoneId,
        orElse: () => GoalMilestone(title: ''),
      );
      if (_timeAudit != null) {
        await _timeAudit!.removeGoalMilestone(_goals[idx], milestone);
      }
      _goals[idx].milestones.removeWhere((m) => m.id == milestoneId);
      _goals[idx].updatedAt = DateTime.now();
      await _save();
    }
  }

  Future<void> setManualProgress(String goalId, double progress) async {
    final idx = _goals.indexWhere((g) => g.id == goalId);
    if (idx != -1) {
      _goals[idx].autoProgress = false;
      _goals[idx].progress = progress.clamp(0.0, 1.0);
      _goals[idx].updatedAt = DateTime.now();
      if (_goals[idx].progress >= 1.0) {
        _goals[idx].status = GoalStatus.achieved;
      }
      await _save();
    }
  }

  /// 时区变化时由上层（通常是 `main.dart` 的 `AppLifecycle.resumed` hook）
  /// 调用；要求 [ReminderScheduler] 按最新 goals 重同步调度队列。
  ///
  /// 当前 [ReminderScheduler] 尚未提供 `syncGoals`（见 Task 14.1），本方法
  /// 以 dynamic-dispatch + try/catch 做兼容：
  /// - 若 `_scheduler` 未注入 → 仅 `debugPrint` 一条跳过日志；
  /// - 若注入的调度器将来补齐 `syncGoals(Iterable<GoalItem>)` → 自动生效；
  /// - 若方法暂缺 → 捕获 `NoSuchMethodError` 并退化为无操作日志。
  ///
  /// TODO(task-14.1): `ReminderScheduler.syncGoals` 落地后移除 dynamic 兜底，
  /// 改为直接调用 `_scheduler!.syncGoals(_goals)`。
  Future<void> onTimezoneChanged() async {
    final scheduler = _scheduler;
    if (scheduler == null) {
      debugPrint(
        '[GoalProvider] onTimezoneChanged skipped: no scheduler attached',
      );
      return;
    }
    try {
      // ignore: avoid_dynamic_calls
      final result = (scheduler as dynamic).syncGoals(List.of(_goals));
      if (result is Future) await result;
    } on NoSuchMethodError {
      // syncGoals 尚未在 ReminderScheduler 上实现（Task 14.1 会补齐）。
      debugPrint(
        '[GoalProvider] onTimezoneChanged: scheduler.syncGoals not yet '
        'implemented; falling back to no-op. TODO(task-14.1)',
      );
    } catch (e, st) {
      debugPrint('[GoalProvider] onTimezoneChanged failed: $e\n$st');
    }
  }

  Future<void> _syncTimeEntriesForGoal(GoalItem prev, GoalItem next) async {
    final prevMap = {for (final m in prev.milestones) m.id: m.isCompleted};
    for (final milestone in next.milestones) {
      final before = prevMap[milestone.id] ?? false;
      await _syncMilestoneEntry(next, milestone, wasCompleted: before);
    }
    for (final milestone in prev.milestones) {
      if (next.milestones.any((m) => m.id == milestone.id)) continue;
      if (milestone.isCompleted) {
        // ignore: discarded_futures
        _timeAudit?.removeGoalMilestone(prev, milestone);
      }
    }
  }

  Future<void> _syncMilestoneEntry(
    GoalItem goal,
    GoalMilestone milestone, {
    required bool wasCompleted,
  }) async {
    if (_timeAudit == null) return;
    if (milestone.isCompleted && !wasCompleted) {
      await _timeAudit!.recordGoalMilestone(goal, milestone);
    } else if (!milestone.isCompleted && wasCompleted) {
      await _timeAudit!.removeGoalMilestone(goal, milestone);
    }
  }
}
