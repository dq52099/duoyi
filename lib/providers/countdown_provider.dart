import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/account_preference_writes.dart';
import '../core/date_item_ui_copy.dart';
import '../models/countdown.dart';
import '../models/goal.dart' show ReminderKind;
import '../services/account_local_data_cleaner.dart';
import '../services/reminder_scheduler.dart';
import 'cloud_sync_provider.dart';

class CountdownProvider extends ChangeNotifier {
  static const _key = 'duoyi_countdowns';
  static const _reminderSyncTimeout = Duration(seconds: 5);
  List<CountdownItem> _items = [];
  ReminderScheduler? _scheduler;
  int _storageGeneration = 0;
  bool _storageLoaded = false;
  bool _disposed = false;
  Future<void> _storageTail = Future<void>.value();
  DateItemReminderIssue? _lastReminderSyncIssue;
  VoidCallback? onLocalMutationPersisted;
  int get storageGeneration => _storageGeneration;
  DateItemReminderIssue? get lastReminderIssue => _lastReminderSyncIssue;

  List<CountdownItem> get items => List.unmodifiable(
    [..._items]..sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      return a.targetDate.compareTo(b.targetDate);
    }),
  );

  String? get lastReminderSyncIssue => _lastReminderSyncIssue == null
      ? null
      : DateItemUiCopy.reminderIssue(
          _lastReminderSyncIssue!,
          anniversary: false,
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

  List<CountdownItem> _decode(SharedPreferences prefs) {
    final loaded = <CountdownItem>[];
    for (final raw in prefs.getStringList(_key) ?? <String>[]) {
      try {
        final json = jsonDecode(raw);
        if (json is Map) {
          loaded.add(CountdownItem.fromJson(Map<String, dynamic>.from(json)));
        }
      } catch (error, stack) {
        debugPrint(
          '[CountdownProvider] skipped invalid record: $error\n$stack',
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
    List<CountdownItem> snapshot,
    AccountPreferenceWriteToken token,
    bool Function() isCurrent, {
    String? deletedId,
    DeletedItemsWriteLease? lease,
  }) async {
    final shouldOffload =
        !kIsWeb &&
        (snapshot.length >= _isolateEncodeMinItems ||
            _estimateCountdownPayloadChars(snapshot) >= _isolateEncodeMinChars);
    final payload = shouldOffload
        ? await compute(_encodeCountdownStoragePayload, snapshot)
        : _encodeCountdownStoragePayload(snapshot);
    _ensureCurrent(token, isCurrent);
    final transaction = AccountPreferenceTransaction(
      prefs,
      () => token.isCurrent && isCurrent(),
    );
    try {
      await transaction.setStringList(_key, payload);
      if (deletedId != null) {
        await CloudSyncProvider.recordDeletedItem(
          'countdowns',
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
        '[CountdownProvider] local mutation callback failed: $error\n$stack',
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
    final snapshot = List<CountdownItem>.of(_items);
    try {
      await scheduler.syncCountdowns(snapshot).timeout(_reminderSyncTimeout);
      if (ownsStorage()) _lastReminderSyncIssue = null;
    } catch (error, stack) {
      if (ownsStorage()) {
        _lastReminderSyncIssue = DateItemReminderIssue.registrationFailed;
      }
      debugPrint('[CountdownProvider] reminder sync failed: $error\n$stack');
    }
    return ownsStorage() ? lastReminderSyncIssue : null;
  }

  Future<String?> addItem(CountdownItem item, {bool Function()? canWrite}) {
    final candidate = item;
    return _upsert(candidate, canWrite: canWrite);
  }

  Future<String?> updateItem(CountdownItem item, {bool Function()? canWrite}) {
    final candidate = item;
    return _upsert(candidate, requireExisting: false, canWrite: canWrite);
  }

  Future<String?> _upsert(
    CountdownItem candidate, {
    bool requireExisting = false,
    bool Function()? canWrite,
  }) => _enqueueStorage((token, isCurrent) async {
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final prefs = await SharedPreferences.getInstance();
    _ensureCurrent(token, isCurrent);
    _hydrate(prefs);
    final snapshot = List<CountdownItem>.of(_items);
    final index = snapshot.indexWhere((item) => item.id == candidate.id);
    if (requireExisting && index < 0) {
      throw StateError('Date item no longer exists');
    }

    if (index < 0) {
      snapshot.add(candidate);
    } else {
      snapshot[index] = candidate;
    }
    await _persist(prefs, snapshot, token, isCurrent);
    return _afterCommit(token, generation, accountGeneration);
  }, canWrite: canWrite);

  Future<CountdownImportSummary> importCountdowns(
    Iterable<CountdownItem> items, {
    bool Function()? canWrite,
  }) {
    final candidates = items.toList();
    return _enqueueStorage((token, isCurrent) async {
      final generation = _storageGeneration;
      final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
      final prefs = await SharedPreferences.getInstance();
      _ensureCurrent(token, isCurrent);
      _hydrate(prefs);
      final snapshot = List<CountdownItem>.of(_items);
      final seen = snapshot.map(_importDuplicateKey).toSet();
      var inserted = 0;
      var skippedDuplicates = 0;
      for (final item in candidates) {
        if (item.title.trim().isEmpty) {
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
      return CountdownImportSummary(
        inserted: inserted,
        skippedDuplicates: skippedDuplicates,
        reminderSyncIssue: issue,
      );
    }, canWrite: canWrite);
  }

  Future<void> deleteItem(String id, {bool Function()? canWrite}) =>
      _enqueueStorage((token, isCurrent) async {
        final generation = _storageGeneration;
        final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
        final prefs = await SharedPreferences.getInstance();
        _ensureCurrent(token, isCurrent);
        _hydrate(prefs);
        final snapshot = List<CountdownItem>.of(_items)
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
    final snapshot = List<CountdownItem>.of(_items);
    final index = snapshot.indexWhere((item) => item.id == id);
    if (index < 0) return;
    if (pinned != null && snapshot[index].isPinned == pinned) return;
    snapshot[index] = snapshot[index].copyWith(
      isPinned: pinned ?? !snapshot[index].isPinned,
    );
    await _persist(prefs, snapshot, token, isCurrent);
    await _afterCommit(
      token,
      generation,
      accountGeneration,
      syncReminders: false,
    );
  }, canWrite: canWrite);
}

class CountdownImportSummary {
  final int inserted;
  final int skippedDuplicates;
  final String? reminderSyncIssue;

  const CountdownImportSummary({
    required this.inserted,
    required this.skippedDuplicates,
    this.reminderSyncIssue,
  });
}

String _importDuplicateKey(CountdownItem item) {
  return jsonEncode([
    item.title.trim().toLowerCase(),
    item.targetDate.toIso8601String(),
    item.categoryIsDefault
        ? ['default']
        : ['custom', item.category.trim().toLowerCase()],
  ]);
}

const int _isolateEncodeMinItems = 500;
const int _isolateEncodeMinChars = 120 * 1024;

int _estimateCountdownPayloadChars(List<CountdownItem> items) {
  var total = 0;
  for (final item in items) {
    total += item.title.length + item.category.length + 160;
    if (total >= _isolateEncodeMinChars) return total;
  }
  return total;
}

List<String> _encodeCountdownStoragePayload(List<CountdownItem> items) =>
    items.map((item) => jsonEncode(item.toJson())).toList();
