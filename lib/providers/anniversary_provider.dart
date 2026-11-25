import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/account_preference_writes.dart';
import '../core/date_item_ui_copy.dart';
import '../models/anniversary.dart';
import '../models/goal.dart' show ReminderKind;
import '../services/account_local_data_cleaner.dart';
import '../services/reminder_scheduler.dart';
import 'cloud_sync_provider.dart';

class AnniversaryProvider extends ChangeNotifier {
  static const _key = 'duoyi_anniversaries_v2';
  static const _reminderSyncTimeout = Duration(seconds: 5);
  List<Anniversary> _items = [];
  ReminderScheduler? _scheduler;
  int _storageGeneration = 0;
  bool _storageLoaded = false;
  bool _disposed = false;
  Future<void> _storageTail = Future<void>.value();
  DateItemReminderIssue? _lastReminderSyncIssue;
  VoidCallback? onLocalMutationPersisted;
  int get storageGeneration => _storageGeneration;
  DateItemReminderIssue? get lastReminderIssue => _lastReminderSyncIssue;

  // Never expose the mutable objects held by the confirmed storage snapshot.
  List<Anniversary> get items => itemsAt(DateTime.now());
  List<Anniversary> itemsAt(DateTime date) {
    final sorted = _items.map(_copy).toList()
      ..sort((a, b) {
        if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
        return a
            .daysRemainingForDate(date)
            .compareTo(b.daysRemainingForDate(date));
      });
    return List.unmodifiable(sorted);
  }

  List<Anniversary> get countdowns => _ofType(AnniversaryType.normal);
  List<Anniversary> get birthdays => _ofType(AnniversaryType.birthday);
  List<Anniversary> get memorials => _ofType(AnniversaryType.memorial);
  List<Anniversary> _ofType(AnniversaryType type) =>
      _items.where((item) => item.type == type).map(_copy).toList();
  List<Anniversary> get upcoming => items.where((item) {
    final days = item.daysRemaining;
    return days >= 0 && days <= 30;
  }).toList();
  static Anniversary _copy(Anniversary item) =>
      Anniversary.fromJson(item.toJson());

  String? get lastReminderSyncIssue => _lastReminderSyncIssue == null
      ? null
      : DateItemUiCopy.reminderIssue(
          _lastReminderSyncIssue!,
          anniversary: true,
        );
  set scheduler(ReminderScheduler? value) => _scheduler = value;

  Future<void> loadFromStorage() =>
      _enqueueStorage<void>((token, isCurrent) async {
        final prefs = await SharedPreferences.getInstance();
        _ensureCurrent(token, isCurrent);
        _items = _decode(prefs);
        _storageLoaded = true;
        notifyListeners();
      });

  List<Anniversary> _decode(SharedPreferences prefs) {
    final loaded = <Anniversary>[];
    for (final raw in prefs.getStringList(_key) ?? <String>[]) {
      try {
        final json = jsonDecode(raw);
        if (json is Map) {
          loaded.add(Anniversary.fromJson(Map<String, dynamic>.from(json)));
        }
      } catch (error, stack) {
        debugPrint(
          '[AnniversaryProvider] skipped invalid record: $error\n$stack',
        );
      }
    }
    return loaded;
  }

  void _hydrate(SharedPreferences prefs) {
    if (_storageLoaded) return;
    _items = _decode(prefs);
    _storageLoaded = true;
  }

  void resetLocalState() {
    _storageGeneration++;
    _storageLoaded = false;
    _items = [];
    _lastReminderSyncIssue = null;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _storageGeneration++;
    super.dispose();
  }

  Future<T> _enqueueStorage<T>(
    Future<T> Function(AccountPreferenceWriteToken, bool Function())
    operation, {
    bool Function()? canWrite,
  }) {
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final preceding = _storageTail;
    // Future.sync also turns a boundary's synchronous cancellation into a Future.
    final result = Future<T>.sync(
      () => AccountPreferenceWrites.runResult<T>((token) async {
        bool isCurrent() {
          try {
            return _ownsStorage(token, generation, accountGeneration) &&
                (canWrite?.call() ?? true);
          } catch (_) {
            return false;
          }
        }

        await preceding;
        _ensureCurrent(token, isCurrent);
        return operation(token, isCurrent);
      }, canceledResult: () => throw const AccountPreferenceWriteCanceled()),
    );
    _storageTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  bool _ownsStorage(
    AccountPreferenceWriteToken token,
    int generation,
    int accountGeneration,
  ) =>
      !_disposed &&
      token.isCurrent &&
      generation == _storageGeneration &&
      AccountLocalDataCleaner.isCurrentAccountDataGeneration(accountGeneration);

  void _ensureCurrent(
    AccountPreferenceWriteToken token,
    bool Function() isCurrent,
  ) {
    token.ensureCurrent();
    if (!isCurrent()) throw const AccountPreferenceWriteCanceled();
  }

  Future<void> _persist(
    SharedPreferences prefs,
    List<Anniversary> snapshot,
    AccountPreferenceWriteToken token,
    bool Function() isCurrent, {
    String? deletedId,
    DeletedItemsWriteLease? lease,
  }) async {
    final shouldOffload =
        !kIsWeb &&
        (snapshot.length >= _isolateEncodeMinItems ||
            _estimateAnniversaryPayloadChars(snapshot) >=
                _isolateEncodeMinChars);
    final payload = shouldOffload
        ? await compute(_encodeAnniversaryStoragePayload, snapshot)
        : _encodeAnniversaryStoragePayload(snapshot);
    _ensureCurrent(token, isCurrent);
    final transaction = AccountPreferenceTransaction(
      prefs,
      () => token.isCurrent && isCurrent(),
    );
    try {
      await transaction.setStringList(_key, payload);
      if (deletedId != null) {
        await CloudSyncProvider.recordDeletedItem(
          'anniversaries',
          deletedId,
          transaction: transaction,
          lease: lease,
        );
      }
      transaction.commit();
      _items = snapshot;
    } catch (_) {
      // Cleanup drains this registered operation, including its rollback.
      await transaction.rollback(canceledBeforeCleanup: true);
      rethrow;
    }
  }

  void _publish(
    AccountPreferenceWriteToken token,
    int generation,
    int accountGeneration,
  ) {
    if (!_ownsStorage(token, generation, accountGeneration)) return;
    try {
      onLocalMutationPersisted?.call();
    } catch (error, stack) {
      debugPrint(
        '[AnniversaryProvider] local mutation callback failed: $error\n$stack',
      );
    }
    if (_ownsStorage(token, generation, accountGeneration)) notifyListeners();
  }

  Future<String?> _afterCommit(
    AccountPreferenceWriteToken token,
    int generation,
    int accountGeneration, {
    bool syncReminders = true,
  }) async {
    _publish(token, generation, accountGeneration);
    bool ownsStorage() => _ownsStorage(token, generation, accountGeneration);
    if (!syncReminders || !ownsStorage()) return null;
    final scheduler = _scheduler;
    if (scheduler == null) {
      _lastReminderSyncIssue =
          _items.any(
            (item) => item.remind && item.reminderKind != ReminderKind.off,
          )
          ? DateItemReminderIssue.serviceUnavailable
          : null;
      return lastReminderSyncIssue;
    }
    final snapshot = _items.map(_copy).toList();
    try {
      await scheduler.syncAnniversaries(snapshot).timeout(_reminderSyncTimeout);
      if (ownsStorage()) _lastReminderSyncIssue = null;
    } catch (error, stack) {
      if (ownsStorage()) {
        _lastReminderSyncIssue = DateItemReminderIssue.registrationFailed;
      }
      debugPrint('[AnniversaryProvider] reminder sync failed: $error\n$stack');
    }
    return ownsStorage() ? lastReminderSyncIssue : null;
  }

  Future<String?> add(Anniversary item, {bool Function()? canWrite}) {
    final candidate = _copy(item);
    return _upsert(candidate, canWrite: canWrite);
  }

  Future<String?> update(Anniversary item, {bool Function()? canWrite}) {
    final candidate = _copy(item);
    return _upsert(candidate, requireExisting: true, canWrite: canWrite);
  }

  Future<String?> _upsert(
    Anniversary candidate, {
    bool requireExisting = false,
    bool Function()? canWrite,
  }) => _enqueueStorage((token, isCurrent) async {
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final prefs = await SharedPreferences.getInstance();
    _ensureCurrent(token, isCurrent);
    _hydrate(prefs);
    final snapshot = List<Anniversary>.of(_items);
    final index = snapshot.indexWhere((item) => item.id == candidate.id);
    if (requireExisting && index < 0) {
      throw StateError('Date item no longer exists');
    }
    candidate.updatedAt = DateTime.now();
    if (index < 0) {
      snapshot.add(candidate);
    } else {
      snapshot[index] = candidate;
    }
    await _persist(prefs, snapshot, token, isCurrent);
    return _afterCommit(token, generation, accountGeneration);
  }, canWrite: canWrite);

  Future<AnniversaryImportSummary> importAnniversaries(
    Iterable<Anniversary> items, {
    bool Function()? canWrite,
  }) {
    final candidates = items.map(_copy).toList();
    return _enqueueStorage((token, isCurrent) async {
      final generation = _storageGeneration;
      final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
      final prefs = await SharedPreferences.getInstance();
      _ensureCurrent(token, isCurrent);
      _hydrate(prefs);
      final snapshot = List<Anniversary>.of(_items);
      final seen = snapshot.map(_importDuplicateKey).toSet();
      var inserted = 0;
      var skippedDuplicates = 0;
      for (final item in candidates) {
        if (item.title.trim().isEmpty) continue;
        if (item.type == AnniversaryType.normal) {
          skippedDuplicates++;
          continue;
        }
        if (!seen.add(_importDuplicateKey(item))) {
          skippedDuplicates++;
          continue;
        }
        snapshot.add(item);
        inserted++;
      }
      String? issue;
      if (inserted > 0) {
        await _persist(prefs, snapshot, token, isCurrent);
        issue = await _afterCommit(token, generation, accountGeneration);
      }
      return AnniversaryImportSummary(
        inserted: inserted,
        skippedDuplicates: skippedDuplicates,
        reminderSyncIssue: issue,
      );
    }, canWrite: canWrite);
  }

  Future<void> delete(String id, {bool Function()? canWrite}) =>
      _enqueueStorage((token, isCurrent) async {
        final generation = _storageGeneration;
        final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
        final prefs = await SharedPreferences.getInstance();
        _ensureCurrent(token, isCurrent);
        _hydrate(prefs);
        final snapshot = List<Anniversary>.of(_items)
          ..removeWhere((item) => item.id == id);
        var committed = false;
        try {
          await CloudSyncProvider.withDeletedItemsLock<void>((lease) async {
            await _persist(
              prefs,
              snapshot,
              token,
              isCurrent,
              deletedId: id,
              lease: lease,
            );
            committed = true;
          });
        } on AccountPreferenceWriteCanceled {
          if (!committed) rethrow;
        }
        await _afterCommit(token, generation, accountGeneration);
      }, canWrite: canWrite);

  Future<void> togglePin(String id, {bool Function()? canWrite}) =>
      _setPinned(id, canWrite: canWrite);

  Future<void> setPinned(String id, bool pinned, {bool Function()? canWrite}) =>
      _setPinned(id, pinned: pinned, canWrite: canWrite);

  Future<void> _setPinned(
    String id, {
    bool? pinned,
    bool Function()? canWrite,
  }) => _enqueueStorage((token, isCurrent) async {
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final prefs = await SharedPreferences.getInstance();
    _ensureCurrent(token, isCurrent);
    _hydrate(prefs);
    final snapshot = List<Anniversary>.of(_items);
    final index = snapshot.indexWhere((item) => item.id == id);
    if (index < 0) return;
    if (pinned != null && snapshot[index].isPinned == pinned) return;
    final item = _copy(snapshot[index]);
    item.isPinned = pinned ?? !item.isPinned;
    item.updatedAt = DateTime.now();
    snapshot[index] = item;
    await _persist(prefs, snapshot, token, isCurrent);
    await _afterCommit(
      token,
      generation,
      accountGeneration,
      syncReminders: false,
    );
  }, canWrite: canWrite);
}

class AnniversaryImportSummary {
  final int inserted;
  final int skippedDuplicates;
  final String? reminderSyncIssue;

  const AnniversaryImportSummary({
    required this.inserted,
    required this.skippedDuplicates,
    this.reminderSyncIssue,
  });
}

String _importDuplicateKey(Anniversary item) {
  return [
    item.title.trim().toLowerCase(),
    item.originDate.toIso8601String(),
    item.type.index,
    item.calendarType.index,
  ].join('|');
}

const int _isolateEncodeMinItems = 500;
const int _isolateEncodeMinChars = 120 * 1024;

int _estimateAnniversaryPayloadChars(List<Anniversary> items) {
  var total = 0;
  for (final item in items) {
    total += item.title.length + (item.description?.length ?? 0) + 192;
    if (total >= _isolateEncodeMinChars) return total;
  }
  return total;
}

List<String> _encodeAnniversaryStoragePayload(List<Anniversary> items) =>
    items.map((item) => jsonEncode(item.toJson())).toList();
