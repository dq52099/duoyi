import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'account_preference_writes.dart';

/// Shared by the provider, backup and sync. Acquire this lane before the
/// tombstone lease, and release it before notifying/reloading providers.
class LocationReminderStorage {
  LocationReminderStorage._();
  static const locationKey = 'duoyi_location_reminders_v1';
  static const tombstoneKey = 'sync_deleted_items';
  static Future<void>? _tail;
  static LocationReminderStorageIndeterminate? _failure;
  static int _storageEpoch = 0;

  static int get storageEpoch => _storageEpoch;
  static LocationReminderStorageIndeterminate? get failure => _failure;

  /// Only confirmed preference removal may retire an account's diagnostic.
  /// The cleaner calls this while holding its boundary and this storage lane.
  static void confirmAccountClearLocked() {
    _storageEpoch++;
    _failure = null;
  }

  static void ensureEpoch(int epoch) {
    if (epoch != _storageEpoch) throw const AccountPreferenceWriteCanceled();
  }

  /// All callers retain this lane and their tombstone lease until verification.
  /// A cancellation generation alone does not prove that storage was cleared.
  static Future<void> compensateLocked(
    AccountPreferenceTransaction transaction,
    Object primaryError, {
    required int account,
    required int epoch,
  }) async {
    final previous = transaction.previousValues;
    final issued = transaction.issuedValues;
    if (previous.isEmpty) return;
    final restorationError = await transaction.rollbackChecked();
    if (restorationError == null) return;
    final diagnostic = LocationReminderStorageIndeterminate(
      primaryError,
      restorationError,
      previous,
      issued,
      account: account,
      epoch: epoch,
    );
    if (epoch == _storageEpoch) _failure = diagnostic;
    throw diagnostic;
  }

  static Future<bool> reconcileLocked(
    SharedPreferences preferences,
    bool Function() isCurrent,
  ) async {
    final diagnostic = _failure;
    if (diagnostic == null) return false;
    void ensureCurrent() {
      ensureEpoch(diagnostic.epoch);
      if (!isCurrent()) throw const AccountPreferenceWriteCanceled();
    }

    ensureCurrent();
    await preferences.reload();
    ensureCurrent();
    final planned = <String, Object?>{};
    for (final entry in diagnostic.previous.entries) {
      final current = preferences.get(entry.key);
      final issued = diagnostic.issued[entry.key];
      if (entry.key == tombstoneKey) {
        planned[entry.key] = _restoreTombstoneDelta(
          entry.value,
          issued,
          current,
          diagnostic,
        );
      } else {
        if (!AccountPreferenceTransaction.valuesEqual(current, entry.value) &&
            !AccountPreferenceTransaction.valuesEqual(current, issued)) {
          throw diagnostic;
        }
        planned[entry.key] = entry.value;
      }
    }
    for (final entry in planned.entries) {
      ensureCurrent();
      try {
        final saved = await AccountPreferenceTransaction.writeValue(
          preferences,
          entry.key,
          entry.value,
        );
        ensureCurrent();
        if (!saved) throw diagnostic;
      } on AccountPreferenceWriteCanceled {
        rethrow;
      } catch (_) {
        throw diagnostic;
      }
    }
    await preferences.reload();
    ensureCurrent();
    if (!planned.entries.every(
      (entry) => AccountPreferenceTransaction.valuesEqual(
        preferences.get(entry.key),
        entry.value,
      ),
    )) {
      throw diagnostic;
    }
    if (identical(_failure, diagnostic)) _failure = null;
    return true;
  }

  static Object? _restoreTombstoneDelta(
    Object? previous,
    Object? issued,
    Object? current,
    LocationReminderStorageIndeterminate diagnostic,
  ) {
    Map<String, Map<String, String>> decode(Object? raw) {
      if (raw == null) return {};
      if (raw is! String) throw diagnostic;
      try {
        final parsed = jsonDecode(raw);
        if (parsed is! Map) throw diagnostic;
        return parsed.map<String, Map<String, String>>((collection, bucket) {
          if (collection is! String || bucket is! Map) throw diagnostic;
          return MapEntry(
            collection,
            bucket.map<String, String>((id, stamp) {
              if (id is! String || stamp is! String) throw diagnostic;
              return MapEntry(id, stamp);
            }),
          );
        });
      } catch (_) {
        throw diagnostic;
      }
    }

    final beforeMap = decode(previous);
    final issuedMap = decode(issued);
    final currentMap = decode(current);
    // Exact original bytes are retained when no independent writer intervened.
    if (current == previous || current == issued) return previous;
    for (final collection in {...beforeMap.keys, ...issuedMap.keys}) {
      final beforeBucket = beforeMap[collection] ?? const <String, String>{};
      final issuedBucket = issuedMap[collection] ?? const <String, String>{};
      for (final id in {...beforeBucket.keys, ...issuedBucket.keys}) {
        final before = beforeBucket[id];
        final attempted = issuedBucket[id];
        if (before == attempted) continue;
        final now = currentMap[collection]?[id];
        if (now != before && now != attempted) throw diagnostic;
        if (before == null) {
          currentMap[collection]?.remove(id);
          if (currentMap[collection]?.isEmpty ?? false) {
            currentMap.remove(collection);
          }
        } else {
          (currentMap[collection] ??= {})[id] = before;
        }
      }
    }
    return jsonEncode(currentMap);
  }

  static Future<T> run<T>(
    Future<T> Function() operation, {
    bool allowUncertain = false,
    int? epoch,
  }) {
    final capturedEpoch = epoch ?? _storageEpoch;
    final previous = _tail;
    final result = Future<T>.sync(() async {
      if (previous != null) await previous;
      ensureEpoch(capturedEpoch);
      final blocked = failure;
      if (!allowUncertain && blocked != null) throw blocked;
      return operation();
    });
    final tail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _tail = tail;
    tail.then<void>((_) {
      if (identical(_tail, tail)) _tail = null;
    });
    return result;
  }
}

class LocationReminderStorageIndeterminate implements Exception {
  final Object primaryError;
  final Object restorationError;
  final Map<String, Object?> previous;
  final Map<String, Object?> issued;
  final int account;
  final int epoch;

  LocationReminderStorageIndeterminate(
    this.primaryError,
    this.restorationError,
    Map<String, Object?> previous,
    Map<String, Object?> issued, {
    this.account = 0,
    int? epoch,
  }) : previous = Map.unmodifiable(
         previous.map(
           (key, value) =>
               MapEntry(key, AccountPreferenceTransaction.freezeValue(value)),
         ),
       ),
       issued = Map.unmodifiable(
         issued.map(
           (key, value) =>
               MapEntry(key, AccountPreferenceTransaction.freezeValue(value)),
         ),
       ),
       epoch = epoch ?? LocationReminderStorage.storageEpoch;
}
