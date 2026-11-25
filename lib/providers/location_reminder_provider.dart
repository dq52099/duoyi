/// 位置提醒引擎与 Provider。
///
/// 不依赖 geolocator 插件以避免引入新依赖；调用方将当前位置喂入
/// [LocationReminderEngine.evaluate]，引擎判定哪些 reminder 命中
/// （并基于 `trigger.enter` / `trigger.leave` 与上次状态做边界检测）。
///
/// 真实定位订阅由上层接入：例如 `geolocator` 后续插件。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/account_preference_writes.dart';
import '../core/location_reminder_storage.dart';
import '../models/location_reminder.dart';
import '../services/account_local_data_cleaner.dart';
import 'cloud_sync_provider.dart';

export '../core/location_reminder_storage.dart'
    show LocationReminderStorageIndeterminate;

class LocationFix {
  final double latitude;
  final double longitude;
  final DateTime at;

  const LocationFix({
    required this.latitude,
    required this.longitude,
    required this.at,
  });
}

class LocationReminderHit {
  final LocationReminder reminder;
  final LocationTrigger triggeredBy;
  final LocationFix fix;

  const LocationReminderHit({
    required this.reminder,
    required this.triggeredBy,
    required this.fix,
  });
}

class LocationReminderEngine {
  LocationReminderEngine._();

  /// Haversine 距离（米）。
  static double distanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const r = 6371000.0;
    double rad(double d) => d * math.pi / 180.0;
    final dLat = rad(lat2 - lat1);
    final dLon = rad(lon2 - lon1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(rad(lat1)) *
            math.cos(rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  /// 给定当前位置与上一轮"是否在范围内"的状态，判定哪些提醒命中。
  ///
  /// [previousInRange] 维护 reminderId → bool 表示上一轮判定。
  /// 返回 (hits, updatedInRange)。
  static (List<LocationReminderHit>, Map<String, bool>) evaluate({
    required List<LocationReminder> reminders,
    required LocationFix fix,
    required Map<String, bool> previousInRange,
    Duration cooldown = const Duration(minutes: 10),
  }) {
    final hits = <LocationReminderHit>[];
    final next = Map<String, bool>.from(previousInRange);
    for (final r in reminders) {
      final d = distanceMeters(
        fix.latitude,
        fix.longitude,
        r.latitude,
        r.longitude,
      );
      final nowInRange = d <= r.radiusMeters;
      final prev = previousInRange[r.id] ?? false;
      next[r.id] = nowInRange;

      final lastFired = r.lastFiredAt;
      if (lastFired != null && fix.at.difference(lastFired).abs() < cooldown) {
        continue;
      }

      final triggered = r.trigger == LocationTrigger.enter
          ? !prev && nowInRange
          : prev && !nowInRange;
      if (triggered) {
        hits.add(
          LocationReminderHit(reminder: r, triggeredBy: r.trigger, fix: fix),
        );
      }
    }
    return (hits, next);
  }
}

class LocationReminderProvider extends ChangeNotifier {
  static const _key = 'duoyi_location_reminders_v1';
  final List<LocationReminder> _reminders = [];
  final Map<String, bool> _inRange = {};
  bool _loaded = false;
  int _storageGeneration = 0;
  bool _disposed = false;
  VoidCallback? onLocalMutationPersisted;

  List<LocationReminder> get reminders =>
      List<LocationReminder>.unmodifiable(_reminders);
  bool get isLoaded => _loaded;
  int get storageGeneration => _storageGeneration;
  bool get storageNeedsReconciliation =>
      LocationReminderStorage.failure != null;

  Future<void> loadFromStorage() => _enqueueStorage<void>((isCurrent) async {
    final prefs = await SharedPreferences.getInstance();
    _ensureCurrent(isCurrent);
    _publish(_decode(prefs.getString(_key)), const {});
    notifyListeners();
  }).onError<AccountPreferenceWriteCanceled>((_, _) {});

  void resetLocalState() {
    if (_disposed) return;
    _storageGeneration++;
    _reminders.clear();
    _inRange.clear();
    _loaded = false;
    notifyListeners();
  }

  Future<void> add(LocationReminder reminder, {bool Function()? isCurrent}) =>
      _mutate<void>((snapshot, range) {
        final existing = snapshot.where((item) => item.id == reminder.id);
        if (existing.isNotEmpty) {
          if (jsonEncode(existing.single.toJson()) !=
              jsonEncode(reminder.toJson())) {
            throw StateError(
              'Location reminder ID already belongs to another draft',
            );
          }
          return _LocationMutation(snapshot, range, null, changed: false);
        }
        snapshot.add(reminder);
        return _LocationMutation(snapshot, range, null);
      }, authority: isCurrent);

  Future<void> update(LocationReminder reminder) {
    final replacement = reminder.copyWith(updatedAt: DateTime.now());
    return _mutate<void>((snapshot, range) {
      final i = snapshot.indexWhere((r) => r.id == replacement.id);
      if (i < 0) {
        return _LocationMutation(snapshot, range, null, changed: false);
      }
      snapshot[i] = replacement;
      range.remove(replacement.id);
      return _LocationMutation(snapshot, range, null);
    });
  }

  Future<void> remove(String id) => _mutate<void>((snapshot, range) {
    final found = snapshot.any((r) => r.id == id);
    snapshot.removeWhere((r) => r.id == id);
    range.remove(id);
    return _LocationMutation(
      snapshot,
      range,
      null,
      changed: found,
      removedIds: found ? [id] : const [],
    );
  });

  /// 注入一次位置更新；返回命中的提醒。
  Future<List<LocationReminderHit>> ingestFix(
    LocationFix fix, {
    bool Function()? isCurrent,
  }) => _mutate<List<LocationReminderHit>>((snapshot, range) {
    final (hits, nextRange) = LocationReminderEngine.evaluate(
      reminders: snapshot,
      fix: fix,
      previousInRange: range,
    );
    final removedIds = <String>[];
    for (final hit in hits) {
      final i = snapshot.indexWhere((r) => r.id == hit.reminder.id);
      if (i < 0) continue;
      if (snapshot[i].oneShot) {
        removedIds.add(snapshot[i].id);
        snapshot.removeAt(i);
        nextRange.remove(hit.reminder.id);
      } else {
        snapshot[i] = snapshot[i].copyWith(lastFiredAt: fix.at);
      }
    }
    return _LocationMutation(
      snapshot,
      nextRange,
      hits,
      changed: hits.isNotEmpty,
      removedIds: removedIds,
    );
  }, authority: isCurrent);

  Future<T> _mutate<T>(
    _LocationMutation<T> Function(List<LocationReminder>, Map<String, bool>)
    prepare, {
    bool Function()? authority,
  }) => _enqueueStorage<T>((isCurrent) async {
    final attemptAccount = AccountLocalDataCleaner.accountDataGeneration;
    final attemptEpoch = LocationReminderStorage.storageEpoch;
    final prefs = await SharedPreferences.getInstance();
    _ensureCurrent(isCurrent);
    final snapshot = _decode(prefs.getString(_key));
    final range = <String, bool>{
      for (final item in snapshot)
        if (_inRange.containsKey(item.id)) item.id: _inRange[item.id]!,
    };
    final mutation = prepare(snapshot, range);
    if (!mutation.changed) {
      _publish(mutation.snapshot, mutation.range);
      return mutation.result;
    }
    var committed = false;
    Future<void> persist({DeletedItemsWriteLease? lease}) async {
      bool ownsWrite() => isCurrent() && (lease?.isCurrent ?? true);
      _ensureCurrent(ownsWrite);
      final transaction = AccountPreferenceTransaction(prefs, ownsWrite);
      try {
        if (lease != null) {
          await CloudSyncProvider.recordDeletedItems(
            'location_reminders',
            mutation.removedIds,
            transaction: transaction,
            lease: lease,
          );
        }
        await transaction.setString(
          _key,
          jsonEncode(mutation.snapshot.map((r) => r.toJson()).toList()),
        );
        transaction.commit();
        committed = true;
        // No await or callbacks between the authority check and publication.
        _publish(mutation.snapshot, mutation.range);
      } catch (error, stack) {
        await LocationReminderStorage.compensateLocked(
          transaction,
          error,
          account: attemptAccount,
          epoch: attemptEpoch,
        );
        Error.throwWithStackTrace(error, stack);
      }
    }

    if (mutation.removedIds.isEmpty) {
      await persist();
    } else {
      try {
        await CloudSyncProvider.withDeletedItemsLock<void>(
          (lease) => persist(lease: lease),
        );
      } on AccountPreferenceWriteCanceled {
        // A boundary after the final durable commit is not an add/delete failure.
        if (!committed) rethrow;
      }
    }
    if (isCurrent()) _notifyLocalMutationPersisted();
    if (isCurrent()) notifyListeners();
    return mutation.result;
  }, authority: authority);

  Future<T> _enqueueStorage<T>(
    Future<T> Function(bool Function()) operation, {
    bool Function()? authority,
    bool allowUncertain = false,
  }) {
    final generation = _storageGeneration;
    final account = AccountLocalDataCleaner.accountDataGeneration;
    final epoch = LocationReminderStorage.storageEpoch;
    return AccountPreferenceWrites.runResult<T>(
      (token) => LocationReminderStorage.run<T>(
        () async {
          bool isCurrent() =>
              !_disposed &&
              token.isCurrent &&
              generation == _storageGeneration &&
              AccountLocalDataCleaner.isCurrentAccountDataGeneration(account) &&
              _authorityCurrent(authority);
          _ensureCurrent(isCurrent);
          return operation(isCurrent);
        },
        allowUncertain: allowUncertain,
        epoch: epoch,
      ),
      canceledResult: () => throw const AccountPreferenceWriteCanceled(),
    );
  }

  /// Explicitly restore an indeterminate write before accepting another draft.
  /// Refuse to overwrite storage changed by an independent writer meanwhile.
  Future<void> reconcileStorage() => _enqueueStorage<void>((isCurrent) async {
    final prefs = await SharedPreferences.getInstance();
    _ensureCurrent(isCurrent);
    if (!storageNeedsReconciliation) return;
    await CloudSyncProvider.withDeletedItemsLock<void>((lease) async {
      bool ownsWrite() => isCurrent() && lease.isCurrent;
      await LocationReminderStorage.reconcileLocked(prefs, ownsWrite);
      _publish(_decode(prefs.getString(_key)), const {});
    });
    if (isCurrent()) notifyListeners();
  }, allowUncertain: true);

  void _ensureCurrent(bool Function() isCurrent) {
    if (!isCurrent()) throw const AccountPreferenceWriteCanceled();
  }

  bool _authorityCurrent(bool Function()? authority) {
    try {
      return authority?.call() ?? true;
    } catch (_) {
      return false;
    }
  }

  List<LocationReminder> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List;
    return list
        .whereType<Map>()
        .map((m) => LocationReminder.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }

  void _publish(List<LocationReminder> snapshot, Map<String, bool> range) {
    _reminders
      ..clear()
      ..addAll(snapshot);
    _inRange
      ..clear()
      ..addAll(range);
    _loaded = true;
  }

  void _notifyLocalMutationPersisted() {
    try {
      onLocalMutationPersisted?.call();
    } catch (e, st) {
      debugPrint('[LocationReminder] committed callback failed: $e\n$st');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _storageGeneration++;
    onLocalMutationPersisted = null;
    super.dispose();
  }
}

class _LocationMutation<T> {
  final List<LocationReminder> snapshot;
  final Map<String, bool> range;
  final T result;
  final bool changed;
  final List<String> removedIds;
  _LocationMutation(
    this.snapshot,
    this.range,
    this.result, {
    this.changed = true,
    this.removedIds = const [],
  });
}
