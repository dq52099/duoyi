import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/account_preference_writes.dart';
import '../core/domain_event_bus.dart';
import '../core/heatmap_calendar.dart';
import '../models/habit.dart';
import '../models/time_entry.dart';
import '../services/account_local_data_cleaner.dart';
import '../services/reminder_scheduler.dart';
import 'cloud_sync_provider.dart';
import 'time_audit_provider.dart';

class HabitProvider extends ChangeNotifier {
  static const Duration _reminderSyncTimeout = Duration(seconds: 5);
  static const String _missingSchedulerIssue = '提醒调度器尚未初始化，请重新打开应用后再保存提醒';

  List<Habit> _habits = [];
  TimeAuditProvider? _timeAudit;
  ReminderScheduler? _scheduler;
  String? _lastReminderSyncIssue;
  DateTime? _lastReminderSyncAttemptAt;
  DateTime? _lastReminderSyncSucceededAt;
  int _storageGeneration = 0;
  bool _storageLoaded = false;
  bool _disposed = false;
  Future<void> _storageQueue = Future<void>.value();
  VoidCallback? onLocalMutationPersisted;

  int _revision = 0;
  int? _cachedDayKey;
  int? _cachedActiveRevision;
  List<Habit>? _cachedActiveHabits;
  int? _cachedEndedRevision;
  List<Habit>? _cachedEndedHabits;
  int? _cachedTagsRevision;
  List<String>? _cachedAllTags;
  int? _cachedStatsRevision;
  int? _cachedStatsDayKey;
  double _cachedTodayOverallProgress = 0;
  int _cachedTodayTotalCompletions = 0;
  double _cachedTodayCompletionRate = 0;
  int? _cachedWeekProgressRevision;
  int? _cachedWeekProgressDayKey;
  List<double>? _cachedWeekProgress;
  int? _cachedCurrentStreakRevision;
  int _cachedCurrentStreak = 0;
  int? _cachedBestStreakRevision;
  int _cachedBestStreak = 0;

  List<Habit> get habits => _habits;

  static int _todayKey(DateTime now) =>
      now.year * 10000 + now.month * 100 + now.day;

  void _bumpRevision() {
    _revision++;
    _cachedActiveHabits = null;
    _cachedEndedHabits = null;
    _cachedAllTags = null;
    _cachedStatsRevision = null;
    _cachedWeekProgress = null;
    _cachedCurrentStreakRevision = null;
    _cachedBestStreakRevision = null;
  }

  List<Habit> get activeHabits {
    final dayKey = _todayKey(DateTime.now());
    if (_cachedDayKey != dayKey) {
      _cachedActiveHabits = null;
      _cachedEndedHabits = null;
      _cachedDayKey = dayKey;
    }
    final cached = _cachedActiveHabits;
    if (cached != null && _cachedActiveRevision == _revision) {
      return cached;
    }
    final result = List<Habit>.unmodifiable(_habits.where((h) => !h.isEnded));
    _cachedActiveRevision = _revision;
    _cachedActiveHabits = result;
    return result;
  }

  List<Habit> get endedHabits {
    final dayKey = _todayKey(DateTime.now());
    if (_cachedDayKey != dayKey) {
      _cachedActiveHabits = null;
      _cachedEndedHabits = null;
      _cachedDayKey = dayKey;
    }
    final cached = _cachedEndedHabits;
    if (cached != null && _cachedEndedRevision == _revision) {
      return cached;
    }
    final result = List<Habit>.unmodifiable(_habits.where((h) => h.isEnded));
    _cachedEndedRevision = _revision;
    _cachedEndedHabits = result;
    return result;
  }

  List<String> get allTags {
    final cached = _cachedAllTags;
    if (cached != null && _cachedTagsRevision == _revision) {
      return cached;
    }
    final tags = <String>{};
    for (final h in _habits) {
      for (final raw in h.tags) {
        final trimmed = raw.trim();
        if (trimmed.isNotEmpty) tags.add(trimmed);
      }
    }
    final sorted = tags.toList()..sort();
    final result = List<String>.unmodifiable(sorted);
    _cachedTagsRevision = _revision;
    _cachedAllTags = result;
    return result;
  }
  String? get lastReminderSyncIssue => _lastReminderSyncIssue;
  DateTime? get lastReminderSyncAttemptAt => _lastReminderSyncAttemptAt;
  DateTime? get lastReminderSyncSucceededAt => _lastReminderSyncSucceededAt;

  void _ensureTodayStats() {
    final dayKey = _todayKey(DateTime.now());
    if (_cachedStatsRevision == _revision && _cachedStatsDayKey == dayKey) {
      return;
    }
    var activeCount = 0;
    var progressSum = 0.0;
    var totalCompletions = 0;
    var completedCount = 0;
    for (final h in _habits) {
      if (!h.isActiveToday()) continue;
      activeCount++;
      progressSum += h.todayProgress();
      totalCompletions += h.todayCount();
      if (h.isCompletedToday()) completedCount++;
    }
    _cachedTodayOverallProgress = activeCount == 0
        ? 0
        : progressSum / activeCount;
    _cachedTodayTotalCompletions = totalCompletions;
    _cachedTodayCompletionRate = activeCount == 0
        ? 0
        : completedCount / activeCount;
    _cachedStatsRevision = _revision;
    _cachedStatsDayKey = dayKey;
  }

  double get todayOverallProgress {
    _ensureTodayStats();
    return _cachedTodayOverallProgress;
  }

  int get todayTotalCompletions {
    _ensureTodayStats();
    return _cachedTodayTotalCompletions;
  }

  double get todayCompletionRate {
    _ensureTodayStats();
    return _cachedTodayCompletionRate;
  }

  int get longestCurrentStreak {
    if (_cachedCurrentStreakRevision == _revision) {
      return _cachedCurrentStreak;
    }
    final maxStreak = _habits.fold(
      0,
      (max, h) => h.currentStreak > max ? h.currentStreak : max,
    );
    _cachedCurrentStreak = maxStreak;
    _cachedCurrentStreakRevision = _revision;
    return maxStreak;
  }

  int get longestBestStreak {
    if (_cachedBestStreakRevision == _revision) {
      return _cachedBestStreak;
    }
    final maxStreak = _habits.fold(
      0,
      (max, h) => h.bestStreak > max ? h.bestStreak : max,
    );
    _cachedBestStreak = maxStreak;
    _cachedBestStreakRevision = _revision;
    return maxStreak;
  }

  // --- Persistence ---

  Future<void> loadFromStorage() {
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final read = _storageQueue.then((_) async {
      if (!_isCurrent(generation, accountGeneration)) return;
      await _readStorage(() => _isCurrent(generation, accountGeneration));
    });
    _storageQueue = read.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return read;
  }

  bool _isCurrent(int generation, int accountGeneration) =>
      !_disposed &&
      generation == _storageGeneration &&
      AccountLocalDataCleaner.isCurrentAccountDataGeneration(accountGeneration);

  Future<void> _readStorage(bool Function() isCurrent) async {
    final prefs = await SharedPreferences.getInstance();
    if (!isCurrent()) return;
    final data = prefs.getString('habits');
    if (data != null) {
      final list = json.decode(data) as List;
      _habits = list
          .map((e) => Habit.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } else {
      _habits = [];
    }
    _storageLoaded = true;
    _bumpRevision();
    notifyListeners();
  }

  void resetLocalState() {
    if (_disposed) return;
    _storageGeneration++;
    _storageLoaded = false;
    _habits = [];
    _bumpRevision();
    _lastReminderSyncIssue = null;
    _lastReminderSyncAttemptAt = null;
    _lastReminderSyncSucceededAt = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _storageGeneration++;
    onLocalMutationPersisted = null;
    super.dispose();
  }

  // ignore: use_setters_to_change_properties
  set timeAudit(TimeAuditProvider? provider) {
    if (_disposed) return;
    _timeAudit = provider;
  }

  // ignore: use_setters_to_change_properties
  set scheduler(ReminderScheduler? scheduler) {
    if (_disposed) return;
    _scheduler = scheduler;
    if (scheduler != null && _lastReminderSyncIssue == _missingSchedulerIssue) {
      _lastReminderSyncIssue = null;
    }
  }

  /// Register the entire operation before yielding. Cleanup drains issued
  /// writes and queued followers; followers retain their original authority.
  Future<T> _enqueueMutation<T>(
    Future<T> Function(bool Function() isCurrent) operation,
  ) {
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    return Future<T>.sync(
      () => AccountPreferenceWrites.runResult<T>((token) {
        bool isCurrent() =>
            token.isCurrent && _isCurrent(generation, accountGeneration);
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

  void _ensureCurrent(bool Function() isCurrent) {
    if (!isCurrent()) throw const AccountPreferenceWriteCanceled();
  }

  List<Habit> _snapshot() => List<Habit>.of(_habits);

  /// Staged models never reach widgets or reward listeners until the platform
  /// acknowledges the snapshot. A failed platform may have changed its cache,
  /// so restore the previous value before releasing this key's queue.
  Future<void> _persistSnapshot(
    List<Habit> next,
    bool Function() isCurrent, {
    String? deletedId,
  }) async {
    _ensureCurrent(isCurrent);
    final data = !kIsWeb && next.length >= _isolateEncodeMinItems
        ? await compute(_encodeHabitStoragePayload, next)
        : json.encode(next.map((habit) => habit.toJson()).toList());
    _ensureCurrent(isCurrent);
    final prefs = await SharedPreferences.getInstance();
    _ensureCurrent(isCurrent);
    Future<void> persist(DeletedItemsWriteLease? lease) async {
      _ensureCurrent(isCurrent);
      final transaction = AccountPreferenceTransaction(prefs, isCurrent);
      try {
        await transaction.setString('habits', data);
        if (deletedId != null) {
          await CloudSyncProvider.recordDeletedItem(
            'habits',
            deletedId,
            transaction: transaction,
            lease: lease,
          );
        }
        transaction.commit();
      } catch (_) {
        // Keep the shared tombstone lock until rollback and reload complete.
        // Account cleanup drains this operation before removing account keys.
        await transaction.rollback(canceledBeforeCleanup: true);
        rethrow;
      }
    }

    if (deletedId == null) {
      await persist(null);
    } else {
      await CloudSyncProvider.withDeletedItemsLock(persist);
    }
    _ensureCurrent(isCurrent);
    _habits = next;
    _bumpRevision();
    _notifyLocalMutationPersisted();
    _ensureCurrent(isCurrent);
  }

  void _notifyLocalMutationPersisted() {
    try {
      onLocalMutationPersisted?.call();
    } catch (e, st) {
      debugPrint('[HabitProvider] local mutation callback failed: $e\n$st');
    }
  }

  Future<void> _syncRemindersNow(bool Function() isCurrent) async {
    if (!isCurrent()) return;
    _lastReminderSyncAttemptAt = DateTime.now();
    final scheduler = _scheduler;
    if (scheduler == null) {
      _lastReminderSyncIssue = _missingSchedulerIssue;
      debugPrint('[HabitProvider] reminder sync skipped: scheduler missing');
      return;
    }
    try {
      await scheduler
          .syncHabits(List.of(_habits))
          .timeout(_reminderSyncTimeout);
      if (!isCurrent()) return;
      _lastReminderSyncIssue = null;
      _lastReminderSyncSucceededAt = DateTime.now();
    } on ReminderScheduleSyncException catch (error, stackTrace) {
      if (!isCurrent()) return;
      _lastReminderSyncIssue = error.failures.isEmpty
          ? '习惯提醒未注册成功，请检查通知权限、弹出提醒兜底、精准闹钟或全屏提醒权限。'
          : error.failures.join('；');
      debugPrint('[HabitProvider] reminder sync failed: $error\n$stackTrace');
    } catch (error, stackTrace) {
      if (!isCurrent()) return;
      _lastReminderSyncIssue = error.toString();
      debugPrint('[HabitProvider] reminder sync failed: $error\n$stackTrace');
    }
  }

  // --- CRUD ---

  Future<void> addHabit(Habit habit) {
    final incoming = habit.copyWith();
    return _enqueueMutation((isCurrent) async {
      if (_habits.any((habit) => habit.id == incoming.id)) return;
      final next = _snapshot()
        ..add(incoming.copyWith(updatedAt: DateTime.now()));
      await _persistSnapshot(next, isCurrent);
      _ensureCurrent(isCurrent);
      DomainEventBus.instance.publish(
        DomainEvent(type: DomainEventType.habitCreated, objectId: incoming.id),
      );
      if (!isCurrent()) return;
      notifyListeners();
      if (!isCurrent()) return;
      await _syncRemindersNow(isCurrent);
      if (isCurrent()) notifyListeners();
    });
  }

  Future<HabitImportSummary> importHabits(Iterable<Habit> habits) {
    final incoming = habits.map((habit) => habit.copyWith()).toList();
    return _enqueueMutation((isCurrent) async {
      final next = _snapshot();
      final insertedIds = <String>[];
      var inserted = 0;
      var skippedDuplicates = 0;
      final existing = next
          .map((habit) => habit.name.trim().toLowerCase())
          .where((name) => name.isNotEmpty)
          .toSet();
      final existingIds = next.map((habit) => habit.id).toSet();
      for (final habit in incoming) {
        final key = habit.name.trim().toLowerCase();
        if (key.isEmpty ||
            existing.contains(key) ||
            existingIds.contains(habit.id)) {
          skippedDuplicates++;
          continue;
        }
        next.add(habit);
        existing.add(key);
        existingIds.add(habit.id);
        inserted++;
        insertedIds.add(habit.id);
      }
      if (inserted > 0) {
        await _persistSnapshot(next, isCurrent);
        for (final id in insertedIds) {
          if (!isCurrent()) break;
          DomainEventBus.instance.publish(
            DomainEvent(type: DomainEventType.habitCreated, objectId: id),
          );
        }
        _ensureCurrent(isCurrent);
        notifyListeners();
        _ensureCurrent(isCurrent);
        await _syncRemindersNow(isCurrent);
        _ensureCurrent(isCurrent);
        notifyListeners();
      }
      return HabitImportSummary(
        inserted: inserted,
        skippedDuplicates: skippedDuplicates,
        reminderSyncIssue: _lastReminderSyncIssue,
      );
    });
  }

  Future<void> incrementHabit(String id) async {
    await incrementHabitForDate(id, DateTime.now());
  }

  Future<void> incrementHabitForDate(String id, DateTime date, {int? amount}) {
    return _enqueueMutation((isCurrent) async {
      final next = _snapshot();
      final idx = next.indexWhere((h) => h.id == id);
      if (idx != -1) {
        final habit = next[idx];
        if (!habit.activeForDate(date)) return;
        final key = habit.dateKey(date);
        final previousCount = habit.completions[key] ?? 0;
        if (habit.kind == HabitKind.positive) {
          if (habit.hasFlexRule) {
            final progress = habit.flexProgressForDate(date);
            if (progress?.isCompleted ?? false) return;
          } else if (previousCount >= habit.targetCount) {
            return;
          }
        }
        final increment = amount ?? _defaultCheckInAmount(habit, previousCount);
        if (increment <= 0) return;
        final updatedHabit = habit.copyWith(updatedAt: habit.updatedAt);
        next[idx] = updatedHabit;
        final stamp = DateTime.now();
        updatedHabit.completions[key] = previousCount + increment;
        updatedHabit.completionUpdatedAt[key] = stamp;
        _recalcStreak(updatedHabit);
        updatedHabit.updatedAt = stamp;
        await _persistSnapshot(next, isCurrent);
        _ensureCurrent(isCurrent);
        DomainEventBus.instance.publish(
          DomainEvent(
            type: DomainEventType.habitCheckedIn,
            objectId: updatedHabit.id,
            metadata: {
              'amount': increment,
              'count': updatedHabit.completions[key] ?? 0,
              'date': key,
            },
          ),
        );
        if (!isCurrent()) return;
        notifyListeners();
        if (!isCurrent()) return;
        final timeAudit = _timeAudit;
        if (timeAudit != null) {
          try {
            await timeAudit.recordHabitCheckIn(
              updatedHabit,
              cumulativeCount: updatedHabit.completions[key] ?? 0,
              amount: increment,
              at: _timeForHabitRecord(date),
            );
          } catch (error, stackTrace) {
            debugPrint(
              '[HabitProvider] recordHabitCheckIn failed: $error\n$stackTrace',
            );
          }
        }
      }
    });
  }

  Future<void> decrementHabit(String id) async {
    await decrementHabitForDate(id, DateTime.now());
  }

  Future<void> decrementHabitForDate(String id, DateTime date) {
    return _enqueueMutation((isCurrent) async {
      final nextHabits = _snapshot();
      final idx = nextHabits.indexWhere((h) => h.id == id);
      if (idx != -1) {
        final habit = nextHabits[idx];
        final key = habit.dateKey(date);
        final v = habit.completions[key] ?? 0;
        if (v > 0) {
          final recordTime = _timeForHabitRecord(date);
          final amount =
              _timeAudit?.habitCheckInRecordedAmount(
                habit,
                count: v,
                at: recordTime,
              ) ??
              _defaultUndoAmount(habit, v);
          final next = v - amount;
          final updatedHabit = habit.copyWith(updatedAt: habit.updatedAt);
          nextHabits[idx] = updatedHabit;
          if (next <= 0) {
            updatedHabit.completions.remove(key);
          } else {
            updatedHabit.completions[key] = next;
          }
          final stamp = DateTime.now();
          updatedHabit.completionUpdatedAt[key] = stamp;
          _recalcStreak(updatedHabit);
          updatedHabit.updatedAt = stamp;
          await _persistSnapshot(nextHabits, isCurrent);
          _ensureCurrent(isCurrent);
          notifyListeners();
          if (!isCurrent()) return;
          final timeAudit = _timeAudit;
          if (timeAudit != null) {
            try {
              await timeAudit.removeHabitCheckIn(
                updatedHabit,
                count: v,
                at: recordTime,
              );
            } catch (error, stackTrace) {
              debugPrint(
                '[HabitProvider] removeHabitCheckIn failed: $error\n$stackTrace',
              );
            }
          }
        }
      }
    });
  }

  int _defaultCheckInAmount(Habit habit, int currentCount) {
    if (habit.kind != HabitKind.positive) return 1;
    if (TimeAuditProvider.habitUnitSeconds(habit) == null) return 1;
    final remaining = habit.targetCount - currentCount;
    return remaining > 0 ? remaining : 1;
  }

  int _defaultUndoAmount(Habit habit, int currentCount) {
    if (habit.kind != HabitKind.positive) return 1;
    if (TimeAuditProvider.habitUnitSeconds(habit) == null) return 1;
    if (currentCount <= habit.targetCount) return currentCount;
    return 1;
  }

  DateTime _timeForHabitRecord(DateTime date) {
    final now = DateTime.now();
    if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day) {
      return now;
    }
    return DateTime(date.year, date.month, date.day, 23, 59);
  }

  void _recalcStreak(Habit h) {
    if (h.hasFlexRule) {
      _recalcFlexStreak(h);
      return;
    }
    int streak = 0;
    final now = DateTime.now();
    for (int i = 0; i < 365; i++) {
      final d = now.subtract(Duration(days: i));
      if (h.isCompletedForDate(d)) {
        streak++;
      } else if (h.isFrozenForDate(d)) {
        // Streak freeze / rest pass preserves streak continuity without adding to streak count.
        continue;
      } else if (i > 0) {
        break;
      }
    }
    h.currentStreak = streak;
    if (streak > h.bestStreak) h.bestStreak = streak;
  }

  void _recalcFlexStreak(Habit h) {
    var streak = 0;
    var bounds = h.periodBoundsForDate(DateTime.now());
    for (int i = 0; i < 120; i++) {
      final completed =
          h.flexProgressForDate(bounds.start)?.isCompleted ?? false;
      if (completed) {
        streak++;
      } else if (i > 0) {
        break;
      }
      bounds = h.previousPeriodBounds(bounds);
    }
    h.currentStreak = streak;
    if (streak > h.bestStreak) h.bestStreak = streak;
  }

  Future<void> deleteHabit(String id) {
    return _enqueueMutation((isCurrent) async {
      final next = _snapshot();
      final idx = next.indexWhere((h) => h.id == id);
      if (idx == -1) return;
      next.removeAt(idx);
      await _persistSnapshot(next, isCurrent, deletedId: id);
      _ensureCurrent(isCurrent);
      await _timeAudit?.deleteBySource(TimeEntrySource.habit, id);
      _ensureCurrent(isCurrent);
      notifyListeners();
      if (!isCurrent()) return;
      await _syncRemindersNow(isCurrent);
      if (isCurrent()) notifyListeners();
    });
  }

  Future<void> endHabit(String id, {DateTime? at}) {
    return _enqueueMutation((isCurrent) async {
      final next = _snapshot();
      final idx = next.indexWhere((h) => h.id == id);
      if (idx == -1) return;
      final base = at ?? DateTime.now();
      final day = DateTime(base.year, base.month, base.day);
      final habit = next[idx];
      final endDate = day.subtract(const Duration(days: 1));
      next[idx] = habit.copyWith(endDate: endDate);
      await _persistSnapshot(next, isCurrent);
      _ensureCurrent(isCurrent);
      notifyListeners();
      if (!isCurrent()) return;
      await _syncRemindersNow(isCurrent);
      if (isCurrent()) notifyListeners();
    });
  }

  Future<void> reopenHabit(String id) {
    return _enqueueMutation((isCurrent) async {
      final next = _snapshot();
      final idx = next.indexWhere((h) => h.id == id);
      if (idx == -1) return;
      final habit = next[idx];
      final restored = habit.copyWith(clearEndDate: true);
      _recalcStreak(restored);
      next[idx] = restored;
      await _persistSnapshot(next, isCurrent);
      _ensureCurrent(isCurrent);
      notifyListeners();
      if (!isCurrent()) return;
      await _syncRemindersNow(isCurrent);
      if (isCurrent()) notifyListeners();
    });
  }

  Future<void> setHabitCheckinNote(String id, DateTime date, String note) {
    return _enqueueMutation((isCurrent) async {
      final next = _snapshot();
      final idx = next.indexWhere((h) => h.id == id);
      if (idx == -1) return;
      final habit = next[idx];
      final key = habit.dateKey(date);
      final trimmed = note.trim();
      final notes = Map<String, String>.from(habit.checkinNotes);
      if (trimmed.isEmpty) {
        notes.remove(key);
      } else {
        notes[key] = trimmed;
      }
      next[idx] = habit.copyWith(
        checkinNotes: notes,
        updatedAt: DateTime.now(),
      );
      await _persistSnapshot(next, isCurrent);
      _ensureCurrent(isCurrent);
      notifyListeners();
    });
  }

  Future<bool> toggleStreakFreezeForDate(String id, DateTime date) {
    return _enqueueMutation((isCurrent) async {
      final next = _snapshot();
      final idx = next.indexWhere((h) => h.id == id);
      if (idx == -1) return false;
      final habit = next[idx];
      final day = DateTime(date.year, date.month, date.day);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      if (day.isAfter(today) || !habit.activeForDate(day)) return false;

      final key = habit.dateKey(day);
      final nextFrozen = List<String>.from(habit.frozenDates);
      var nextTokens = habit.freezeTokens;
      if (nextFrozen.contains(key)) {
        nextFrozen.remove(key);
        nextTokens = (nextTokens + 1).clamp(0, 99).toInt();
      } else {
        if (habit.isCompletedForDate(day) || nextTokens <= 0) {
          return false;
        }
        nextFrozen.add(key);
        nextTokens = (nextTokens - 1).clamp(0, 99).toInt();
      }
      final updated = habit.copyWith(
        freezeTokens: nextTokens,
        frozenDates: nextFrozen,
        updatedAt: DateTime.now(),
      );
      _recalcStreak(updated);
      next[idx] = updated;
      await _persistSnapshot(next, isCurrent);
      _ensureCurrent(isCurrent);
      notifyListeners();
      return true;
    });
  }

  Future<void> addStreakFreezeTokens(String id, int delta) {
    return _enqueueMutation((isCurrent) async {
      final next = _snapshot();
      final idx = next.indexWhere((h) => h.id == id);
      if (idx == -1) return;
      final habit = next[idx];
      final nextTokens = (habit.freezeTokens + delta).clamp(0, 99).toInt();
      if (nextTokens == habit.freezeTokens) return;
      next[idx] = habit.copyWith(
        freezeTokens: nextTokens,
        updatedAt: DateTime.now(),
      );
      await _persistSnapshot(next, isCurrent);
      _ensureCurrent(isCurrent);
      notifyListeners();
    });
  }

  Future<void> updateHabit(String id, Habit updated) {
    final incoming = updated.copyWith();
    return _enqueueMutation((isCurrent) async {
      final next = _snapshot();
      final idx = next.indexWhere((h) => h.id == id);
      if (idx != -1) {
        // The configuration form may predate queued widget check-ins. Counts
        // and their deletion timestamps belong to the latest activity state.
        final current = next[idx];
        next[idx] = incoming.copyWith(
          completions: current.completions,
          completionUpdatedAt: current.completionUpdatedAt,
          checkinNotes: current.checkinNotes,
          freezeTokens: current.freezeTokens,
          frozenDates: current.frozenDates,
          currentStreak: current.currentStreak,
          bestStreak: current.bestStreak,
          updatedAt: DateTime.now(),
        );
        await _persistSnapshot(next, isCurrent);
        _ensureCurrent(isCurrent);
        notifyListeners();
        if (!isCurrent()) return;
        await _syncRemindersNow(isCurrent);
        if (isCurrent()) notifyListeners();
      }
    });
  }

  // --- Heatmap ---

  Map<String, int> combinedHeatmap(int weeks, {DateTime? today}) {
    final data = <String, int>{};
    final window = HeatmapCalendarWindow(weeks: weeks, today: today);
    for (final date in window.visibleDays) {
      final key = HeatmapCalendarWindow.dateKey(date);
      final active = _habits.where((h) => h.activeForDate(date)).toList();
      if (active.isEmpty) {
        data[key] = 0;
        continue;
      }
      final progress =
          active.fold(0.0, (sum, h) => sum + h.progressForDate(date)) /
          active.length;
      data[key] = HeatmapCalendarWindow.progressLevel(progress);
    }
    return data;
  }

  // --- Weekly stats ---

  List<double> last7DaysCompletion() {
    final now = DateTime.now();
    return List<double>.generate(7, (i) {
      final d = now.subtract(Duration(days: 6 - i));
      final active = _habits.where((h) => h.activeForDate(d)).toList();
      if (active.isEmpty) return 0.0;
      return active.where((h) => h.isCompletedForDate(d)).length /
          active.length;
    });
  }

  bool _habitExistsOnDate(Habit habit, DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    final start = habit.startDate == null
        ? DateTime(
            habit.createdAt.year,
            habit.createdAt.month,
            habit.createdAt.day,
          )
        : DateTime(
            habit.startDate!.year,
            habit.startDate!.month,
            habit.startDate!.day,
          );
    return !day.isBefore(start);
  }

  List<double> currentWeekProgress() {
    final now = DateTime.now();
    final dayKey = _todayKey(now);
    final cached = _cachedWeekProgress;
    if (cached != null &&
        _cachedWeekProgressRevision == _revision &&
        _cachedWeekProgressDayKey == dayKey) {
      return cached;
    }
    final weekStart = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));
    final result = List<double>.unmodifiable(
      List<double>.generate(7, (i) {
        final d = weekStart.add(Duration(days: i));
        var activeCount = 0;
        var sum = 0.0;
        for (final h in _habits) {
          if (!_habitExistsOnDate(h, d) || !h.activeForDate(d)) continue;
          activeCount++;
          sum += h.progressForDate(d);
        }
        if (activeCount == 0) return 0.0;
        return sum / activeCount;
      }, growable: false),
    );
    _cachedWeekProgressRevision = _revision;
    _cachedWeekProgressDayKey = dayKey;
    _cachedWeekProgress = result;
    return result;
  }

  // --- Reorder ---

  Future<void> reorder(List<String> orderedIds) {
    final requested = List<String>.of(orderedIds);
    return _enqueueMutation((isCurrent) async {
      final map = {for (final h in _snapshot()) h.id: h};
      final newList = <Habit>[];
      for (int i = 0; i < requested.length; i++) {
        final h = map[requested[i]];
        if (h != null) {
          newList.add(
            h.sortOrder == i
                ? h
                : h.copyWith(sortOrder: i, updatedAt: DateTime.now()),
          );
          map.remove(requested[i]);
        }
      }
      newList.addAll(map.values);
      await _persistSnapshot(newList, isCurrent);
      _ensureCurrent(isCurrent);
      notifyListeners();
    });
  }
}

class HabitImportSummary {
  final int inserted;
  final int skippedDuplicates;
  final String? reminderSyncIssue;

  const HabitImportSummary({
    required this.inserted,
    required this.skippedDuplicates,
    this.reminderSyncIssue,
  });
}

/// 单文件本地持久化的 JSON 编码条数阈值：超过后挪到后台 isolate 编码。
const int _isolateEncodeMinItems = 500;

String _encodeHabitStoragePayload(List<Habit> habits) =>
    json.encode(habits.map((e) => e.toJson()).toList());
