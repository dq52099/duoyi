import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'account_preference_writes.dart';

/// Shared configuration/cache lane; HTTP requests never hold this lane.
class IcsSubscriptionStorage {
  IcsSubscriptionStorage._();

  static const subscriptionsKey = 'duoyi_ics_subscriptions_v1';
  static Future<void>? _tail;
  static int _epoch = 0;
  static IcsStorageIndeterminate? _failure;
  static final Map<String, int> _sourceRevisions = {};
  static final Map<String, int> _requests = {};

  static int get epoch => _epoch;
  static IcsStorageIndeterminate? get failure => _failure;
  static int sourceRevision(String id) => _sourceRevisions[id] ?? 0;
  static void sourceChanged(String id) {
    _sourceRevisions[id] = sourceRevision(id) + 1;
  }

  static int beginRequest(String id) =>
      _requests[id] = (_requests[id] ?? 0) + 1;
  static bool ownsRequest(String id, int request) => _requests[id] == request;

  /// Called only after authoritative account removal while holding this lane.
  static void confirmAccountClearLocked() {
    _epoch++;
    _failure = null;
    _sourceRevisions.clear();
    _requests.clear();
  }

  static void ensureEpoch(int expected) {
    if (expected != _epoch) throw const AccountPreferenceWriteCanceled();
  }

  static Future<T> run<T>(
    Future<T> Function() operation, {
    required int epoch,
    bool allowUncertain = false,
  }) {
    final previous = _tail;
    final result = Future<T>.sync(() async {
      if (previous != null) await previous;
      ensureEpoch(epoch);
      if (!allowUncertain && _failure != null) throw _failure!;
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

  static Future<void> compensateLocked(
    SharedPreferences preferences,
    AccountPreferenceTransaction transaction,
    Object error, {
    required int epoch,
  }) async {
    if (transaction.previousValues.isEmpty) return;
    final diagnostic = IcsStorageIndeterminate(
      error,
      transaction.previousValues,
      transaction.issuedValues,
      epoch,
    );
    try {
      // Compensation must finish even when cleanup has invalidated the caller.
      await _restore(preferences, diagnostic, () => epoch == _epoch);
    } catch (_) {
      if (epoch == _epoch) _failure = diagnostic;
      throw diagnostic;
    }
  }

  static Future<bool> reconcileLocked(
    SharedPreferences preferences,
    bool Function() isCurrent,
  ) async {
    final diagnostic = _failure;
    if (diagnostic == null) return false;
    await _restore(preferences, diagnostic, isCurrent);
    if (identical(_failure, diagnostic)) _failure = null;
    return true;
  }

  static Future<void> _restore(
    SharedPreferences preferences,
    IcsStorageIndeterminate diagnostic,
    bool Function() isCurrent,
  ) async {
    void ensureCurrent() {
      ensureEpoch(diagnostic.epoch);
      if (!isCurrent()) throw const AccountPreferenceWriteCanceled();
    }

    ensureCurrent();
    await preferences.reload();
    ensureCurrent();
    final planned = <String, Object?>{};
    // Refuse independent changes to affected entries before issuing any writes.
    for (final entry in diagnostic.previous.entries) {
      final current = preferences.get(entry.key);
      final issued = diagnostic.issued[entry.key];
      if (entry.key == subscriptionsKey) {
        planned[entry.key] = _restoreSubscriptionDelta(
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
    for (final entry in planned.entries.toList().reversed) {
      ensureCurrent();
      try {
        await AccountPreferenceTransaction.writeValue(
          preferences,
          entry.key,
          entry.value,
        );
      } catch (_) {
        // Reload below decides whether a rejected restoration took effect.
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
  }

  static Object? _restoreSubscriptionDelta(
    Object? previous,
    Object? issued,
    Object? current,
    IcsStorageIndeterminate diagnostic,
  ) {
    if (current == previous || current == issued) return previous;
    Map<String, Map<String, dynamic>> decode(Object? raw) {
      if (raw == null) return {};
      if (raw is! String) throw diagnostic;
      try {
        final list = jsonDecode(raw);
        if (list is! List) throw diagnostic;
        final result = <String, Map<String, dynamic>>{};
        for (final value in list) {
          if (value is! Map || value['id'] is! String) throw diagnostic;
          final id = value['id'] as String;
          if (result.containsKey(id)) throw diagnostic;
          result[id] = Map<String, dynamic>.from(value);
        }
        return result;
      } catch (_) {
        throw diagnostic;
      }
    }

    bool same(Map<String, dynamic>? a, Map<String, dynamic>? b) {
      if (a == null || b == null) return a == b;
      return a.length == b.length &&
          a.keys.every((key) => b.containsKey(key) && a[key] == b[key]);
    }

    final before = decode(previous);
    final attempted = decode(issued);
    final now = decode(current);
    for (final id in {...before.keys, ...attempted.keys}) {
      if (same(before[id], attempted[id])) continue;
      if (!same(now[id], before[id]) && !same(now[id], attempted[id])) {
        throw diagnostic;
      }
      if (before[id] == null) {
        now.remove(id);
      } else {
        now[id] = before[id]!;
      }
    }
    return jsonEncode(now.values.toList());
  }
}

class IcsStorageIndeterminate implements Exception {
  final Object primaryError;
  final Map<String, Object?> previous;
  final Map<String, Object?> issued;
  final int epoch;

  IcsStorageIndeterminate(
    this.primaryError,
    Map<String, Object?> previous,
    Map<String, Object?> issued,
    this.epoch,
  ) : previous = Map.unmodifiable(previous),
      issued = Map.unmodifiable(issued);
}
