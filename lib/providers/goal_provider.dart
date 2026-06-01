import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/domain_event_bus.dart';
import '../core/recommended_goals.dart';
import '../models/goal.dart';
import '../services/reminder_scheduler.dart';
import 'cloud_sync_provider.dart';
import 'time_audit_provider.dart';

class GoalProvider extends ChangeNotifier {
  static const _key = 'duoyi_goals';
  static const Duration _reminderSyncTimeout = Duration(seconds: 5);
  List<GoalItem> _goals = [];
  TimeAuditProvider? _timeAudit;
  ReminderScheduler? _scheduler;

  Future<void> Function()? _reminderResyncRequester;

  // ignore: use_setters_to_change_properties
  set reminderResyncRequester(Future<void> Function()? requester) {
    _reminderResyncRequester = requester;
  }

  // ignore: use_setters_to_change_properties
  set scheduler(ReminderScheduler? scheduler) {
    _scheduler = scheduler;
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

  Future<void> _syncGoalRemindersNow() async {
    final scheduler = _scheduler;
    if (scheduler == null) return;
    try {
      await scheduler.syncGoals(List.of(_goals)).timeout(_reminderSyncTimeout);
    } catch (error, stackTrace) {
      debugPrint('[GoalProvider] reminder sync failed: $error\n$stackTrace');
    }
  }

  Future<void> add(GoalItem goal) async {
    _goals.add(goal);
    DomainEventBus.instance.publish(
      DomainEvent(type: DomainEventType.goalCreated, objectId: goal.id),
    );
    await _save();
    await _syncGoalRemindersNow();
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
    await _syncGoalRemindersNow();
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
      await _syncGoalRemindersNow();
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
    await CloudSyncProvider.recordDeletedItem('goals', id);
    _goals.removeWhere((g) => g.id == id);
    await _save();
    await _syncGoalRemindersNow();
  }

  Future<void> setStatus(String id, GoalStatus status) async {
    final idx = _goals.indexWhere((g) => g.id == id);
    if (idx != -1) {
      _goals[idx].status = status;
      if (status == GoalStatus.achieved) _goals[idx].progress = 1.0;
      _goals[idx].updatedAt = DateTime.now();
      await _save();
      await _syncGoalRemindersNow();
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
      await _syncGoalRemindersNow();
      await _syncMilestoneEntry(_goals[idx], m, wasCompleted: wasCompleted);
    }
  }

  Future<void> addMilestone(String goalId, String title) async {
    final idx = _goals.indexWhere((g) => g.id == goalId);
    if (idx != -1) {
      _goals[idx].milestones.add(GoalMilestone(title: title));
      _goals[idx].updatedAt = DateTime.now();
      await _save();
      await _syncGoalRemindersNow();
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
      await _syncGoalRemindersNow();
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
      await _syncGoalRemindersNow();
    }
  }

  /// 时区或跨日派发命中后由上层触发提醒重放。
  ///
  /// 普通写入路径由 Provider 写侧做局部同步；这个显式 hook 只请求全量队列
  /// 合并，避免和启动、权限、云同步重放并发双跑。
  Future<void> onTimezoneChanged() async {
    final requester = _reminderResyncRequester;
    if (requester == null) {
      debugPrint(
        '[GoalProvider] onTimezoneChanged skipped: no reminder resync requester',
      );
      return;
    }
    try {
      await requester();
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
