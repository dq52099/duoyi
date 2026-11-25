import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/account_preference_writes.dart';
import '../models/goal.dart';
import '../models/habit.dart';
import '../models/time_entry.dart';
import '../models/todo.dart';
import '../services/account_local_data_cleaner.dart';
import 'cloud_sync_provider.dart';

class TimeEntryImportSummary {
  final int inserted;
  final int skippedDuplicates;

  const TimeEntryImportSummary({
    required this.inserted,
    required this.skippedDuplicates,
  });
}

class TimeAuditProvider extends ChangeNotifier {
  static const storageKey = 'duoyi_time_entries';

  List<TimeEntry> _entries = [];
  int _storageGeneration = 0;
  // Keep writes and rollback ordered even when a disposed instance is replaced.
  static Future<void>? _storageTail;
  bool _disposed = false;
  VoidCallback? onLocalMutationPersisted;

  /// Identifies the data owner captured by an editor before an account reset.
  int get storageGeneration => _storageGeneration;
  bool get isDisposed => _disposed;

  @override
  void dispose() {
    _disposed = true;
    _storageGeneration++;
    onLocalMutationPersisted = null;
    super.dispose();
  }

  List<TimeEntry> get entries {
    final sorted = [..._entries]
      ..sort((a, b) => b.startAt.compareTo(a.startAt));
    return List.unmodifiable(sorted);
  }

  /// Capture ownership before queueing so cleanup can drain every issued write.
  Future<T> _enqueueStorage<T>(
    Future<T> Function(bool Function() isCurrent) operation, {
    required T Function() canceledResult,
  }) {
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final preceding = _storageTail;
    bool ownsData() =>
        _isCurrentStorageGeneration(generation, accountGeneration);
    final result = Future<T>.sync(() {
      return AccountPreferenceWrites.runResult<T>((token) async {
        if (preceding != null) await preceding;
        if (!ownsData()) return canceledResult();
        token.ensureCurrent();
        try {
          return await operation(() => ownsData() && token.isCurrent);
        } on AccountPreferenceWriteCanceled {
          // A reset/disposed owner must not receive completion effects. A token
          // invalidated before account cleanup changes its generation is still
          // a rejected save, never an acknowledged commit for a current editor.
          if (!ownsData()) return canceledResult();
          rethrow;
        }
      }, canceledResult: () => throw const AccountPreferenceWriteCanceled());
    });
    final tail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _storageTail = tail;
    tail.then<void>((_) {
      if (identical(_storageTail, tail)) _storageTail = null;
    });
    return result;
  }

  void _ensureCurrent(bool Function() isCurrent) {
    if (!isCurrent()) throw const AccountPreferenceWriteCanceled();
  }

  Future<void> loadFromStorage() async {
    if (_disposed) return;
    await _enqueueStorage<void>((isCurrent) async {
      final prefs = await SharedPreferences.getInstance();
      _ensureCurrent(isCurrent);
      final raw = prefs.getStringList(storageKey) ?? const <String>[];
      _entries = raw
          .map((value) {
            try {
              return TimeEntry.fromJson(
                jsonDecode(value) as Map<String, dynamic>,
              );
            } catch (_) {
              return null;
            }
          })
          .whereType<TimeEntry>()
          .toList();
      notifyListeners();
    }, canceledResult: () {});
  }

  /// Capture durable identities without treating a reset/unhydrated cache as
  /// proof that a completion record has already disappeared.
  Future<List<TimeEntry>> readStoredEntries() =>
      _enqueueStorage<List<TimeEntry>>((isCurrent) async {
        final prefs = await SharedPreferences.getInstance();
        _ensureCurrent(isCurrent);
        await prefs.reload();
        _ensureCurrent(isCurrent);
        return List.unmodifiable(_decodeStoredEntries(prefs));
      }, canceledResult: () => throw const AccountPreferenceWriteCanceled());

  List<TimeEntry> _decodeStoredEntries(SharedPreferences prefs) =>
      (prefs.getStringList(storageKey) ?? const <String>[])
          .map((raw) {
            try {
              return TimeEntry.fromJson(
                jsonDecode(raw) as Map<String, dynamic>,
              );
            } catch (_) {
              return null;
            }
          })
          .whereType<TimeEntry>()
          .toList();

  /// Remove only the original, unchanged records. The durable read and removal
  /// share a queue so a replacement cache cannot consume a pending cleanup.
  Future<void> deleteStoredEntries(Map<String, String> originalPayloads) =>
      _enqueueStorage<void>((isCurrent) async {
        final prefs = await SharedPreferences.getInstance();
        _ensureCurrent(isCurrent);
        await prefs.reload();
        _ensureCurrent(isCurrent);
        final stored = _decodeStoredEntries(prefs);
        final removed = stored
            .where(
              (entry) =>
                  originalPayloads[entry.id] == jsonEncode(entry.toJson()),
            )
            .map((entry) => entry.id)
            .toSet();
        if (removed.isEmpty) return;
        await _persistSnapshot(
          stored.where((entry) => !removed.contains(entry.id)).toList(),
          isCurrent,
          deletedIds: removed.toList(),
        );
      }, canceledResult: () => throw const AccountPreferenceWriteCanceled());

  void resetLocalState() {
    if (_disposed) return;
    _storageGeneration++;
    _entries = [];
    notifyListeners();
  }

  /// Publish only platform-acknowledged data. Rollback stays in this key's
  /// queue, and account cleanup drains it before removing the account keys.
  Future<void> _persistSnapshot(
    List<TimeEntry> snapshot,
    bool Function() isCurrent, {
    List<String> deletedIds = const [],
  }) async {
    _ensureCurrent(isCurrent);
    final data = snapshot.length >= _isolateEncodeMinItems
        ? await compute(_encodeTimeAuditPayload, snapshot)
        : snapshot.map((entry) => jsonEncode(entry.toJson())).toList();
    _ensureCurrent(isCurrent);
    final prefs = await SharedPreferences.getInstance();
    _ensureCurrent(isCurrent);
    Future<void> persist(DeletedItemsWriteLease? lease) async {
      _ensureCurrent(isCurrent);
      final transaction = AccountPreferenceTransaction(prefs, isCurrent);
      try {
        await transaction.setStringList(storageKey, data);
        if (deletedIds.isNotEmpty) {
          await CloudSyncProvider.recordDeletedItems(
            'time_entries',
            deletedIds,
            workspaceId: null,
            transaction: transaction,
            lease: lease,
          );
        }
        transaction.commit();
      } catch (_) {
        // The tombstone lease must also cover restoration of both keys.
        await transaction.rollback(canceledBeforeCleanup: true);
        rethrow;
      }
    }

    if (deletedIds.isEmpty) {
      await persist(null);
    } else {
      await CloudSyncProvider.withDeletedItemsLock(persist);
    }
    _ensureCurrent(isCurrent);
    _entries = snapshot;
    _notifyLocalMutationPersisted();
    if (isCurrent()) notifyListeners();
  }

  void _notifyLocalMutationPersisted() {
    if (_disposed) return;
    try {
      onLocalMutationPersisted?.call();
    } catch (e, st) {
      debugPrint('[TimeAuditProvider] local mutation callback failed: $e\n$st');
    }
  }

  bool _isCurrentStorageGeneration(
    int storageGeneration,
    int accountGeneration,
  ) {
    return !_disposed &&
        storageGeneration == _storageGeneration &&
        AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          accountGeneration,
        );
  }

  Future<void> add(TimeEntry entry) async {
    if (_disposed) return;
    await _enqueueStorage<void>((isCurrent) async {
      if (_entries.any((item) => item.id == entry.id)) {
        throw StateError('Time entry already exists');
      }
      await _persistSnapshot([..._entries, entry], isCurrent);
    }, canceledResult: () {});
  }

  Future<TimeEntryImportSummary> importTimeEntries(
    Iterable<TimeEntry> entries,
  ) async {
    const empty = TimeEntryImportSummary(inserted: 0, skippedDuplicates: 0);
    if (_disposed) return empty;
    final incoming = entries.toList(growable: false);
    return _enqueueStorage<TimeEntryImportSummary>((isCurrent) async {
      var inserted = 0;
      var skippedDuplicates = 0;
      final snapshot = List<TimeEntry>.of(_entries);
      final seen = _entries.map(_importDuplicateKey).toSet();
      final ids = snapshot.map((entry) => entry.id).toSet();
      for (final entry in incoming) {
        final key = _importDuplicateKey(entry);
        if (seen.contains(key) || ids.contains(entry.id)) {
          skippedDuplicates++;
          continue;
        }
        seen.add(key);
        ids.add(entry.id);
        snapshot.add(entry);
        inserted++;
      }
      if (inserted > 0) await _persistSnapshot(snapshot, isCurrent);
      return TimeEntryImportSummary(
        inserted: inserted,
        skippedDuplicates: skippedDuplicates,
      );
    }, canceledResult: () => empty);
  }

  Future<void> upsertAuto(TimeEntry entry) async {
    if (_disposed) return;
    await _enqueueStorage<void>((isCurrent) async {
      final key = entry.dedupeKey;
      final snapshot = List<TimeEntry>.of(_entries);
      final index = snapshot.indexWhere(
        (item) =>
            item.id == entry.id ||
            (key != null && key.isNotEmpty && item.dedupeKey == key),
      );
      if (index < 0) {
        snapshot.add(entry);
      } else {
        snapshot[index] = entry.copyWith();
      }
      await _persistSnapshot(snapshot, isCurrent);
    }, canceledResult: () {});
  }

  // TimeEntry records use account-private deletion markers, with no workspaceId.
  Future<void> deleteByDedupeKey(String dedupeKey) =>
      deleteWhere((entry) => entry.dedupeKey == dedupeKey);

  Future<void> deleteWhere(bool Function(TimeEntry entry) test) async {
    if (_disposed) return;
    await _enqueueStorage<void>((isCurrent) async {
      final removedIds = _entries.where(test).map((entry) => entry.id).toList();
      if (removedIds.isEmpty) return;
      final removed = removedIds.toSet();
      final snapshot = _entries
          .where((entry) => !removed.contains(entry.id))
          .toList();
      await _persistSnapshot(snapshot, isCurrent, deletedIds: removedIds);
    }, canceledResult: () {});
  }

  Future<void> deleteBySource(TimeEntrySource source, String sourceId) =>
      deleteWhere(
        (entry) => entry.source == source && entry.sourceId == sourceId,
      );

  Future<void> deleteGoalEntries(String goalId) => deleteWhere((entry) {
    if (entry.source != TimeEntrySource.goal) return false;
    final sourceId = entry.sourceId;
    return sourceId == goalId || sourceId?.startsWith('$goalId:') == true;
  });

  Future<void> update(TimeEntry entry) async {
    if (_disposed) return;
    await _enqueueStorage<void>((isCurrent) async {
      final snapshot = List<TimeEntry>.of(_entries);
      final index = snapshot.indexWhere((item) => item.id == entry.id);
      if (index < 0) throw StateError('Time entry no longer exists');
      snapshot[index] = entry;
      await _persistSnapshot(snapshot, isCurrent);
    }, canceledResult: () {});
  }

  Future<void> delete(String id) => deleteWhere((entry) => entry.id == id);

  Future<void> recordPomodoroSession({
    required String sessionId,
    required String title,
    required DateTime startAt,
    required DateTime endAt,
    String? note,
  }) async {
    await upsertAuto(
      TimeEntry(
        title: title,
        startAt: startAt,
        endAt: endAt,
        category: TimeEntryCategory.focus,
        source: TimeEntrySource.pomodoro,
        sourceId: sessionId,
        dedupeKey: pomodoroDedupeKey(sessionId),
        note: note ?? '',
      ),
    );
  }

  Future<void> recordTodoCompletion(
    TodoItem todo, {
    DateTime? completedAt,
  }) async {
    final durationSeconds = _todoDurationSeconds(todo);
    if (durationSeconds == null || durationSeconds <= 0) return;
    final endAt = completedAt ?? todo.completedAt ?? DateTime.now();
    await upsertAuto(
      TimeEntry(
        title: todo.title,
        startAt: endAt.subtract(Duration(seconds: durationSeconds)),
        endAt: endAt,
        category: TimeEntryCategory.todo,
        source: TimeEntrySource.todo,
        sourceId: todo.id,
        dedupeKey: todoCompletionDedupeKey(todo.id, endAt),
        note: todo.dueDate == null ? '' : '截止：${todo.dueDate}',
      ),
    );
  }

  Future<void> removeTodoCompletion(
    TodoItem todo, {
    DateTime? completedAt,
  }) async {
    final at = completedAt ?? todo.completedAt;
    if (at == null) return;
    await deleteByDedupeKey(todoCompletionDedupeKey(todo.id, at));
  }

  Future<void> recordHabitCheckIn(
    Habit habit, {
    required int cumulativeCount,
    int amount = 1,
    DateTime? at,
  }) async {
    final seconds = _habitDurationSeconds(habit, amount);
    if (seconds == null || seconds <= 0) return;
    final endAt = at ?? DateTime.now();
    final dayKey = _dateKey(endAt);
    await upsertAuto(
      TimeEntry(
        title: habit.name,
        startAt: endAt.subtract(Duration(seconds: seconds)),
        endAt: endAt,
        category: TimeEntryCategory.habit,
        source: TimeEntrySource.habit,
        sourceId: habit.id,
        dedupeKey: habitCheckInDedupeKey(habit.id, dayKey, cumulativeCount),
        note: habit.unit == null ? '' : '单位：${habit.unit}',
      ),
    );
  }

  Future<void> removeHabitCheckIn(
    Habit habit, {
    required int count,
    DateTime? at,
  }) async {
    final endAt = at ?? DateTime.now();
    await deleteByDedupeKey(
      habitCheckInDedupeKey(habit.id, _dateKey(endAt), count),
    );
  }

  int? habitCheckInRecordedAmount(
    Habit habit, {
    required int count,
    DateTime? at,
  }) {
    final unitSeconds = habitUnitSeconds(habit);
    if (unitSeconds == null || unitSeconds <= 0) return null;
    final endAt = at ?? DateTime.now();
    final key = habitCheckInDedupeKey(habit.id, _dateKey(endAt), count);
    for (final entry in _entries) {
      if (entry.dedupeKey == key && entry.durationSeconds > 0) {
        final amount = entry.durationSeconds ~/ unitSeconds;
        return amount > 0 ? amount : null;
      }
    }
    return null;
  }

  Future<void> recordGoalMilestone(
    GoalItem goal,
    GoalMilestone milestone, {
    DateTime? completedAt,
  }) async {
    final durationSeconds = _goalDurationSeconds(goal);
    if (durationSeconds == null || durationSeconds <= 0) return;
    final endAt = completedAt ?? milestone.completedAt ?? DateTime.now();
    await upsertAuto(
      TimeEntry(
        title: '${goal.title} · ${milestone.title}',
        startAt: endAt.subtract(Duration(seconds: durationSeconds)),
        endAt: endAt,
        category: TimeEntryCategory.goal,
        source: TimeEntrySource.goal,
        sourceId: '${goal.id}:${milestone.id}',
        dedupeKey: goalMilestoneDedupeKey(goal.id, milestone.id),
        note: goal.timeTargetSeconds != null
            ? '目标时长：${goal.timeTargetSeconds! ~/ 60} 分钟'
            : '',
      ),
    );
  }

  Future<void> removeGoalMilestone(
    GoalItem goal,
    GoalMilestone milestone,
  ) async {
    await deleteByDedupeKey(goalMilestoneDedupeKey(goal.id, milestone.id));
  }

  List<TimeEntry> entriesInRange(DateTime start, DateTime end) {
    return entries.where((e) => e.overlaps(start, end)).toList();
  }

  List<TimeEntry> entriesForDate(DateTime date) {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    return entriesInRange(start, end);
  }

  int totalSecondsInRange(DateTime start, DateTime end) {
    return entriesInRange(
      start,
      end,
    ).fold<int>(0, (sum, entry) => sum + _durationWithin(entry, start, end));
  }

  Map<TimeEntryCategory, int> secondsByCategory(DateTime start, DateTime end) {
    final result = <TimeEntryCategory, int>{
      for (final c in TimeEntryCategory.values) c: 0,
    };
    for (final entry in entriesInRange(start, end)) {
      result[entry.category] =
          (result[entry.category] ?? 0) + _durationWithin(entry, start, end);
    }
    return result;
  }

  Map<String, int> secondsByDay(DateTime start, DateTime end) {
    final result = <String, int>{};
    for (final entry in entriesInRange(start, end)) {
      result[entry.dayKey] =
          (result[entry.dayKey] ?? 0) + _durationWithin(entry, start, end);
    }
    return result;
  }

  Map<String, int> secondsBySource(DateTime start, DateTime end) {
    final result = <String, int>{};
    for (final entry in entriesInRange(start, end)) {
      final key = entry.source.label;
      result[key] = (result[key] ?? 0) + _durationWithin(entry, start, end);
    }
    return result;
  }

  static String pomodoroDedupeKey(String sessionId) => 'pomodoro:$sessionId';

  static String todoCompletionDedupeKey(String todoId, DateTime completedAt) =>
      'todo:$todoId:${completedAt.millisecondsSinceEpoch}';

  static String habitCheckInDedupeKey(
    String habitId,
    String dateKey,
    int count,
  ) => 'habit:$habitId:$dateKey:$count';

  static String goalMilestoneDedupeKey(String goalId, String milestoneId) =>
      'goal:$goalId:milestone:$milestoneId';

  static int? habitUnitSeconds(Habit habit) {
    final unit = habit.unit?.trim();
    if (unit == null || unit.isEmpty) return null;
    final lower = unit.toLowerCase();
    if (unit.contains('小时') || lower.contains('hour') || lower == 'h') {
      return 3600;
    }
    if (unit.contains('分钟') ||
        unit.contains('分') ||
        lower.contains('min') ||
        lower == 'm') {
      return 60;
    }
    return null;
  }

  int? _todoDurationSeconds(TodoItem todo) {
    if (todo.timeTargetSeconds != null && todo.timeTargetSeconds! > 0) {
      return todo.timeTargetSeconds;
    }
    if (todo.focusLink.enabled &&
        todo.focusLink.focusSeconds != null &&
        todo.focusLink.focusSeconds! > 0) {
      return todo.focusLink.focusSeconds;
    }
    return null;
  }

  int? _habitDurationSeconds(Habit habit, int count) {
    final unitSeconds = habitUnitSeconds(habit);
    return unitSeconds == null ? null : count * unitSeconds;
  }

  int? _goalDurationSeconds(GoalItem goal) {
    if (goal.timeTargetSeconds != null && goal.timeTargetSeconds! > 0) {
      return goal.timeTargetSeconds;
    }
    if (goal.focusLink.enabled &&
        goal.focusLink.focusSeconds != null &&
        goal.focusLink.focusSeconds! > 0) {
      return goal.focusLink.focusSeconds;
    }
    return null;
  }

  int _durationWithin(TimeEntry entry, DateTime start, DateTime end) {
    final clippedStart = entry.startAt.isBefore(start) ? start : entry.startAt;
    final clippedEnd = entry.endAt.isAfter(end) ? end : entry.endAt;
    return math.max(0, clippedEnd.difference(clippedStart).inSeconds);
  }

  String _importDuplicateKey(TimeEntry entry) {
    final normalizedTitle = entry.title.trim().toLowerCase();
    final source = entry.sourceId?.trim().isNotEmpty == true
        ? '${entry.source.name}:${entry.sourceId}'
        : entry.source.name;
    return [
      normalizedTitle,
      entry.startAt.toIso8601String(),
      entry.endAt.toIso8601String(),
      entry.category.name,
      source,
    ].join('|');
  }

  String _dateKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

/// 单文件本地持久化的 JSON 编码条数阈值：超过后挪到后台 isolate 编码。
const int _isolateEncodeMinItems = 500;

List<String> _encodeTimeAuditPayload(List<TimeEntry> entries) =>
    entries.map((e) => jsonEncode(e.toJson())).toList();
