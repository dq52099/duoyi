import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/account_preference_writes.dart';
import '../core/domain_event_bus.dart';
import '../core/recommended_goals.dart';
import '../models/goal.dart';
import '../models/recurrence.dart';
import '../services/account_local_data_cleaner.dart';
import '../services/reminder_scheduler.dart';
import 'cloud_sync_provider.dart';
import 'time_audit_provider.dart';

class GoalProvider extends ChangeNotifier {
  static const _key = 'duoyi_goals';
  static const Duration _reminderSyncTimeout = Duration(seconds: 5);
  List<GoalItem> _goals = [];
  TimeAuditProvider? _timeAudit;
  ReminderScheduler? _scheduler;
  int _storageGeneration = 0;
  bool _storageLoaded = false;
  int? _loadedAccountGeneration;
  int _storageReadRevision = 0;
  bool _disposed = false;
  Future<void> _storageQueue = Future<void>.value();
  VoidCallback? onLocalMutationPersisted;

  /// Optional live workspace permission supplied by the application shell.
  bool Function(String workspaceId)? canEditWorkspace;
  Future<void> Function()? _reminderResyncRequester;

  /// Retained forms use this together with provider identity and account scope.
  int get storageGeneration => _storageGeneration;
  int get storageReadRevision => _storageReadRevision;
  bool get isStorageHydrated =>
      !_disposed &&
      _storageLoaded &&
      _loadedAccountGeneration != null &&
      AccountLocalDataCleaner.isCurrentAccountDataGeneration(
        _loadedAccountGeneration!,
      );

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
    final sorted = _snapshot();
    sorted.sort((a, b) {
      int statusRank(GoalItem goal) => switch (goal.status) {
        GoalStatus.active => 0,
        GoalStatus.achieved => 1,
        GoalStatus.paused => 2,
        GoalStatus.abandoned => 3,
      };
      final status = statusRank(a).compareTo(statusRank(b));
      return status != 0 ? status : a.sortOrder.compareTo(b.sortOrder);
    });
    return List.unmodifiable(sorted);
  }

  List<GoalItem> get activeGoals => List.unmodifiable(
    _goals.where((goal) => goal.status == GoalStatus.active).map(_clone),
  );

  // GoalItem and milestones are mutable. Callers and staged writes must not
  // share them with the acknowledged model.
  static GoalItem _clone(GoalItem goal) => GoalItem(
    id: goal.id,
    title: goal.title,
    description: goal.description,
    icon: goal.icon,
    colorValue: goal.colorValue,
    startDate: goal.startDate,
    targetDate: goal.targetDate,
    status: goal.status,
    progress: goal.progress,
    autoProgress: goal.autoProgress,
    milestones: goal.milestones.map(_cloneMilestone).toList(),
    category: goal.category,
    recurrence: RecurrenceRule(
      frequency: goal.recurrence.frequency,
      interval: goal.recurrence.interval,
      byWeekdays: goal.recurrence.byWeekdays == null
          ? null
          : List<int>.of(goal.recurrence.byWeekdays!),
      byMonthDay: goal.recurrence.byMonthDay,
      endDate: goal.recurrence.endDate,
      maxOccurrences: goal.recurrence.maxOccurrences,
    ),
    scheduling: GoalScheduling(
      mode: goal.scheduling.mode,
      fixedWeekdays: goal.scheduling.fixedWeekdays == null
          ? null
          : List<int>.of(goal.scheduling.fixedWeekdays!),
      fixedMonthDays: goal.scheduling.fixedMonthDays == null
          ? null
          : List<int>.of(goal.scheduling.fixedMonthDays!),
      randomMinGapDays: goal.scheduling.randomMinGapDays,
      randomMaxPerWeek: goal.scheduling.randomMaxPerWeek,
      randomMaxPerMonth: goal.scheduling.randomMaxPerMonth,
    ),
    skipHolidays: goal.skipHolidays,
    focusLink: goal.focusLink,
    reminder: goal.reminder,
    reminderPlan: goal.reminderPlan,
    timeTargetSeconds: goal.timeTargetSeconds,
    dailyTargetCount: goal.dailyTargetCount,
    sortOrder: goal.sortOrder,
    workspaceId: goal.workspaceId,
    createdAt: goal.createdAt,
    updatedAt: goal.updatedAt,
  );

  List<GoalItem> _snapshot() => _goals.map(_clone).toList();

  bool _isCurrent(int generation, int accountGeneration) =>
      !_disposed &&
      generation == _storageGeneration &&
      AccountLocalDataCleaner.isCurrentAccountDataGeneration(accountGeneration);

  void _ensureCurrent(bool Function() isCurrent) {
    if (!isCurrent()) throw const AccountPreferenceWriteCanceled();
  }

  bool _canEdit(String workspaceId) =>
      canEditWorkspace?.call(workspaceId) ?? true;

  void _ensureCanEdit(Iterable<String> workspaces) {
    if (!workspaces.every(_canEdit)) {
      throw StateError('Goal workspace is read-only');
    }
  }

  Future<void> _readStorage(bool Function() isCurrent) async {
    final prefs = await SharedPreferences.getInstance();
    _ensureCurrent(isCurrent);
    final loaded = (prefs.getStringList(_key) ?? [])
        .map((raw) => GoalItem.fromJson(jsonDecode(raw)))
        .toList();
    _ensureCurrent(isCurrent);
    _goals = loaded;
    _storageLoaded = true;
    _loadedAccountGeneration = AccountLocalDataCleaner.accountDataGeneration;
  }

  Future<void> loadFromStorage() {
    if (_disposed) return Future<void>.value();
    _storageLoaded = false;
    _loadedAccountGeneration = null;
    final readRevision = ++_storageReadRevision;
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    bool ownsRead() =>
        _isCurrent(generation, accountGeneration) &&
        readRevision == _storageReadRevision;
    final result = _storageQueue.then((_) async {
      if (!ownsRead()) return;
      if (AccountPreferenceWrites.isBoundaryActive) {
        _deferStorageRead(ownsRead);
        return;
      }
      bool isCurrent() =>
          ownsRead() && !AccountPreferenceWrites.isBoundaryActive;
      try {
        await _readStorage(isCurrent);
        _ensureCurrent(isCurrent);
        notifyListeners();
      } on AccountPreferenceWriteCanceled {
        if (ownsRead() && AccountPreferenceWrites.isBoundaryActive) {
          _storageLoaded = false;
          _loadedAccountGeneration = null;
          _deferStorageRead(ownsRead);
        }
      }
    });
    _storageQueue = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  void _deferStorageRead(bool Function() ownsRead) {
    // Account preflight awaits onSynced. Waiting on its boundary inside the
    // storage queue would prevent that preflight from ever finishing.
    unawaited(() async {
      try {
        await AccountPreferenceWrites.waitForBoundary();
        if (ownsRead()) await loadFromStorage();
      } catch (error, stack) {
        debugPrint('[Goal] deferred storage read failed: $error\n$stack');
      }
    }());
  }

  void resetLocalState() {
    if (_disposed) return;
    _storageGeneration++;
    _storageLoaded = false;
    _loadedAccountGeneration = null;
    _goals = [];
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _storageGeneration++;
    onLocalMutationPersisted = null;
    canEditWorkspace = null;
    super.dispose();
  }

  /// Register before yielding so cleanup drains issued writes and followers.
  Future<T> _enqueueMutation<T>(
    Future<T> Function(bool Function() isCurrent) operation, {
    bool Function()? canWrite,
  }) {
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    return Future<T>.sync(
      () => AccountPreferenceWrites.runResult<T>((token) {
        bool isCurrent() =>
            token.isCurrent &&
            _isCurrent(generation, accountGeneration) &&
            canWrite?.call() != false;
        final result = _storageQueue.then<T>((_) async {
          _ensureCurrent(isCurrent);
          if (!_storageLoaded) await _readStorage(isCurrent);
          _ensureCurrent(isCurrent);
          return operation(isCurrent);
        });
        _storageQueue = result.then<void>(
          (_) {},
          onError: (Object _, StackTrace _) {},
        );
        return result;
      }, canceledResult: () => throw const AccountPreferenceWriteCanceled()),
    );
  }

  Future<void> _persistSnapshot(
    List<GoalItem> next,
    bool Function() isCurrent, {
    required Set<String> workspaces,
    List<GoalItem> deletedGoals = const [],
  }) async {
    _ensureCurrent(isCurrent);
    _ensureCanEdit(workspaces);
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final preferenceGeneration = AccountPreferenceWrites.generation;
    var committed = false;
    final data = (!kIsWeb && next.length >= _isolateEncodeMinItems)
        ? await compute(_encodeGoalStoragePayload, next)
        : _encodeGoalStoragePayload(next);
    _ensureCurrent(isCurrent);
    final prefs = await SharedPreferences.getInstance();
    bool canPersist() => isCurrent() && workspaces.every(_canEdit);
    _ensureCurrent(canPersist);

    Future<void> persist(DeletedItemsWriteLease? lease) async {
      _ensureCurrent(canPersist);
      final transaction = AccountPreferenceTransaction(prefs, canPersist);
      try {
        await transaction.setStringList(_key, data);
        for (final goal in deletedGoals) {
          await CloudSyncProvider.recordDeletedItem(
            'goals',
            goal.id,
            workspaceId: goal.workspaceId,
            transaction: transaction,
            lease: lease,
          );
        }
        transaction.commit();
        committed = true;
      } catch (_) {
        // Keep the shared deletion-record lock through rollback and reload.
        await transaction.rollback(canceledBeforeCleanup: true);
        rethrow;
      }
      // Publish in the same continuation as commit. Authority lost after a
      // successful ACK can suppress effects, but cannot reject that save or
      // leave memory describing the snapshot that preceded it.
      _goals = next;
    }

    try {
      if (deletedGoals.isEmpty) {
        await persist(null);
      } else {
        await CloudSyncProvider.withDeletedItemsLock(persist);
      }
    } on AccountPreferenceWriteCanceled {
      // The tombstone lock checks its own lease on return. Losing that lease
      // after commit must preserve the acknowledged operation's success.
      if (!committed) rethrow;
    }
    // Callbacks may start account cleanup or enqueue another tombstone writer;
    // invoke them after releasing the shared lock and only in this account.
    if (_isCurrent(generation, accountGeneration) &&
        preferenceGeneration == AccountPreferenceWrites.generation &&
        !AccountPreferenceWrites.isBoundaryActive) {
      _notifyLocalMutationPersisted();
    }
  }

  void _notifyLocalMutationPersisted() {
    try {
      onLocalMutationPersisted?.call();
    } catch (error, stack) {
      debugPrint(
        '[GoalProvider] local mutation callback failed: $error\n$stack',
      );
    }
  }

  Future<void> _syncGoalRemindersNow(bool Function() isCurrent) async {
    final scheduler = _scheduler;
    if (scheduler == null || !isCurrent()) return;
    try {
      await scheduler.syncGoals(_snapshot()).timeout(_reminderSyncTimeout);
    } catch (error, stack) {
      debugPrint('[GoalProvider] reminder sync failed: $error\n$stack');
    }
  }

  Future<void> add(GoalItem goal, {bool Function()? canWrite}) {
    final incoming = _clone(goal);
    return _enqueueMutation((isCurrent) async {
      _ensureCanEdit([incoming.workspaceId]);
      if (_goals.any((goal) => goal.id == incoming.id)) return;
      final next = _snapshot()..add(incoming);
      await _persistSnapshot(
        next,
        isCurrent,
        workspaces: {incoming.workspaceId},
      );
      bool canFinish() => isCurrent() && _canEdit(incoming.workspaceId);
      if (!canFinish()) return;
      DomainEventBus.instance.publish(
        DomainEvent(type: DomainEventType.goalCreated, objectId: incoming.id),
      );
      if (!canFinish()) return;
      notifyListeners();
      await _syncGoalRemindersNow(canFinish);
    }, canWrite: canWrite);
  }

  /// Instantiate and persist a recommendation through the same write contract.
  Future<GoalItem> applyRecommended(
    RecommendedGoal recommendation, {
    DateTime? targetDate,
    bool Function()? canWrite,
  }) async {
    if (recommendation.requiresTargetDate && targetDate == null) {
      throw ArgumentError.notNull('targetDate');
    }
    final goal = RecommendedGoalsLibrary.instantiate(
      recommendation,
      targetDate: targetDate,
    );
    await add(goal, canWrite: canWrite);
    return _clone(goal);
  }

  Future<void> update(GoalItem goal, {bool Function()? canWrite}) {
    final incoming = _clone(goal)..updatedAt = DateTime.now();
    return _mutateGoal(incoming.id, (_) => incoming, canWrite: canWrite);
  }

  Future<void> _mutateGoal(
    String id,
    GoalItem Function(GoalItem draft) change, {
    bool rewardMilestones = false,
    bool Function()? canWrite,
  }) => _enqueueMutation((isCurrent) async {
    final next = _snapshot();
    final index = next.indexWhere((goal) => goal.id == id);
    if (index < 0) throw StateError('Goal no longer exists');
    final previous = _clone(next[index]);
    final changed = change(next[index])..updatedAt = DateTime.now();
    final workspaces = {previous.workspaceId, changed.workspaceId};
    _ensureCanEdit(workspaces);
    next[index] = changed;
    await _persistSnapshot(next, isCurrent, workspaces: workspaces);
    bool canFinish() => isCurrent() && workspaces.every(_canEdit);
    if (!canFinish()) return;
    if (rewardMilestones) {
      final before = {
        for (final milestone in previous.milestones)
          milestone.id: milestone.isCompleted,
      };
      for (final milestone in changed.milestones) {
        if (!canFinish()) return;
        if (milestone.isCompleted && before[milestone.id] != true) {
          DomainEventBus.instance.publish(
            DomainEvent(
              type: DomainEventType.goalMilestoneCompleted,
              objectId: milestone.id,
              metadata: {'goalId': id},
            ),
          );
        }
      }
    }
    if (!canFinish()) return;
    if (previous.status != GoalStatus.achieved &&
        changed.status == GoalStatus.achieved) {
      DomainEventBus.instance.publish(
        DomainEvent(type: DomainEventType.goalAchieved, objectId: id),
      );
    }
    if (!canFinish()) return;
    notifyListeners();
    if (!canFinish()) return;
    await _syncTimeEntriesForGoal(previous, changed, canFinish);
    await _syncGoalRemindersNow(canFinish);
  }, canWrite: canWrite);

  Future<void> delete(
    String id, {
    bool Function()? canWrite,
  }) => _enqueueMutation((isCurrent) async {
    final deleted = _goals.where((goal) => goal.id == id).map(_clone).toList();
    if (deleted.isEmpty) return;
    final workspaces = deleted.map((goal) => goal.workspaceId).toSet();
    _ensureCanEdit(workspaces);
    final next = _snapshot()..removeWhere((goal) => goal.id == id);
    await _persistSnapshot(
      next,
      isCurrent,
      workspaces: workspaces,
      deletedGoals: deleted,
    );
    bool canFinish() => isCurrent() && workspaces.every(_canEdit);
    if (!canFinish()) return;
    notifyListeners();
    if (!canFinish()) return;
    final audit = _timeAudit;
    if (audit != null) {
      try {
        await audit.deleteGoalEntries(id);
      } catch (error, stack) {
        debugPrint('[GoalProvider] time entry cleanup failed: $error\n$stack');
      }
    }
    await _syncGoalRemindersNow(canFinish);
  }, canWrite: canWrite);

  Future<void> setStatus(String id, GoalStatus status) =>
      _mutateGoal(id, (draft) {
        draft.status = status;
        if (status == GoalStatus.achieved) draft.progress = 1.0;
        return draft;
      });

  Future<void> toggleMilestone(String goalId, String milestoneId) =>
      _mutateGoal(goalId, (draft) {
        final milestone = draft.milestones
            .where((milestone) => milestone.id == milestoneId)
            .firstOrNull;
        if (milestone == null) throw StateError('Milestone no longer exists');
        milestone.isCompleted = !milestone.isCompleted;
        milestone.completedAt = milestone.isCompleted ? DateTime.now() : null;
        if (draft.autoProgress &&
            draft.milestones.every((milestone) => milestone.isCompleted) &&
            draft.status == GoalStatus.active) {
          draft.status = GoalStatus.achieved;
          draft.progress = 1.0;
        } else if (draft.autoProgress &&
            draft.status == GoalStatus.achieved &&
            !milestone.isCompleted) {
          draft.status = GoalStatus.active;
        }
        return draft;
      }, rewardMilestones: true);

  Future<void> addMilestone(String goalId, String title) =>
      _mutateGoal(goalId, (draft) {
        draft.milestones.add(GoalMilestone(title: title));
        return draft;
      });

  Future<void> removeMilestone(String goalId, String milestoneId) =>
      _mutateGoal(goalId, (draft) {
        draft.milestones.removeWhere(
          (milestone) => milestone.id == milestoneId,
        );
        return draft;
      });

  Future<void> setManualProgress(String goalId, double progress) =>
      _mutateGoal(goalId, (draft) {
        draft.autoProgress = false;
        draft.progress = progress.clamp(0.0, 1.0);
        if (draft.progress >= 1.0) draft.status = GoalStatus.achieved;
        return draft;
      });

  /// Timezone/day changes request the existing full reminder replay queue.
  Future<void> onTimezoneChanged() async {
    final requester = _reminderResyncRequester;
    if (requester == null || _disposed) return;
    try {
      await requester();
    } catch (error, stack) {
      debugPrint('[GoalProvider] onTimezoneChanged failed: $error\n$stack');
    }
  }

  Future<void> _syncTimeEntriesForGoal(
    GoalItem previous,
    GoalItem next,
    bool Function() isCurrent,
  ) async {
    final audit = _timeAudit;
    if (audit == null) return;
    bool canFinish() => isCurrent() && identical(_timeAudit, audit);
    final before = {
      for (final milestone in previous.milestones)
        milestone.id: milestone.isCompleted,
    };
    try {
      for (final milestone in next.milestones) {
        if (!canFinish()) return;
        final wasCompleted = before[milestone.id] ?? false;
        if (milestone.isCompleted && !wasCompleted) {
          await audit.recordGoalMilestone(
            _clone(next),
            _cloneMilestone(milestone),
          );
        } else if (!milestone.isCompleted && wasCompleted) {
          await audit.removeGoalMilestone(
            _clone(next),
            _cloneMilestone(milestone),
          );
        }
      }
      for (final milestone in previous.milestones) {
        if (!canFinish()) return;
        if (milestone.isCompleted &&
            !next.milestones.any((item) => item.id == milestone.id)) {
          await audit.removeGoalMilestone(
            _clone(previous),
            _cloneMilestone(milestone),
          );
        }
      }
    } catch (error, stack) {
      // Goal storage is acknowledged; an auxiliary failure must not turn that
      // success into a retry that repeats the primary mutation.
      debugPrint('[GoalProvider] time entry sync failed: $error\n$stack');
    }
  }

  static GoalMilestone _cloneMilestone(GoalMilestone milestone) =>
      GoalMilestone(
        id: milestone.id,
        title: milestone.title,
        isCompleted: milestone.isCompleted,
        completedAt: milestone.completedAt,
      );
}

const int _isolateEncodeMinItems = 500;

List<String> _encodeGoalStoragePayload(List<GoalItem> goals) =>
    goals.map((goal) => jsonEncode(goal.toJson())).toList();
