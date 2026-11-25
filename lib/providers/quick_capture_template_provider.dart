import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/account_preference_writes.dart';
import '../models/quick_capture_template.dart';
import '../services/account_local_data_cleaner.dart';
import 'cloud_sync_provider.dart';

class QuickCaptureTemplateProvider extends ChangeNotifier {
  static const _storageKey = 'duoyi_quick_capture_templates_v1';

  final List<QuickCaptureTemplate> _customTemplates = [];
  int _storageGeneration = 0;
  bool _storageLoaded = false;
  bool _disposed = false;
  Future<void> _storageTail = Future<void>.value();
  VoidCallback? onLocalMutationPersisted;

  int get storageGeneration => _storageGeneration;

  List<QuickCaptureTemplate> get customTemplates =>
      List.unmodifiable(_customTemplates);

  List<QuickCaptureTemplate> get templates => List.unmodifiable([
    ...QuickCaptureTemplate.builtIns(),
    ..._customTemplates,
  ]);

  Future<void> loadFromStorage() => _enqueueStorage((isCurrent) async {
    final prefs = await SharedPreferences.getInstance();
    _ensureCurrent(isCurrent);
    _publish(_decode(prefs.getString(_storageKey)));
    notifyListeners();
  });

  void resetLocalState() {
    _storageGeneration++;
    _storageLoaded = false;
    _customTemplates.clear();
    if (!_disposed) notifyListeners();
  }

  /// Only publish a new template after its platform write is acknowledged.
  Future<void> saveTemplate(QuickCaptureTemplate template) =>
      _enqueueStorage((isCurrent) async {
        final prefs = await SharedPreferences.getInstance();
        _ensureCurrent(isCurrent);
        final snapshot = _snapshot(prefs);
        final custom = template.copyWith(builtIn: false);
        final index = snapshot.indexWhere((item) => item.id == custom.id);
        if (index < 0) {
          snapshot.add(custom);
        } else {
          snapshot[index] = custom;
        }
        final transaction = AccountPreferenceTransaction(prefs, isCurrent);
        try {
          await _persist(transaction, snapshot);
          transaction.commit();
        } catch (_) {
          // Cleanup drains this issued operation before removing account keys.
          await transaction.rollback(canceledBeforeCleanup: true);
          rethrow;
        }
        _ensureCurrent(isCurrent);
        _publish(snapshot);
        _notifyLocalMutationPersisted();
        if (isCurrent()) notifyListeners();
      });

  Future<void> deleteTemplate(String id) => _enqueueStorage((isCurrent) async {
    final snapshot = await CloudSyncProvider.withDeletedItemsLock((
      lease,
    ) async {
      _ensureCurrent(isCurrent);
      final prefs = await SharedPreferences.getInstance();
      bool ownsTransaction() => isCurrent() && lease.isCurrent;
      _ensureCurrent(ownsTransaction);
      final snapshot = _snapshot(prefs);
      snapshot.removeWhere((item) => item.id == id && !item.builtIn);
      final transaction = AccountPreferenceTransaction(prefs, ownsTransaction);
      try {
        await CloudSyncProvider.recordDeletedItem(
          'quick_capture_templates',
          id,
          transaction: transaction,
          lease: lease,
        );
        _ensureCurrent(ownsTransaction);
        await _persist(transaction, snapshot);
        transaction.commit();
      } catch (_) {
        // Rollback remains inside the tombstone lock so another collection's
        // successful delete cannot be overwritten by this operation's failure.
        await transaction.rollback(canceledBeforeCleanup: true);
        rethrow;
      }
      return snapshot;
    });
    _ensureCurrent(isCurrent);
    _publish(snapshot);
    _notifyLocalMutationPersisted();
    if (isCurrent()) notifyListeners();
  });

  Future<void> _enqueueStorage(
    Future<void> Function(bool Function()) operation,
  ) {
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final preceding = _storageTail;
    final result = AccountPreferenceWrites.runResult<void>((token) async {
      bool isCurrent() =>
          !_disposed &&
          token.isCurrent &&
          generation == _storageGeneration &&
          AccountLocalDataCleaner.isCurrentAccountDataGeneration(
            accountGeneration,
          );
      await preceding;
      _ensureCurrent(isCurrent);
      await operation(isCurrent);
    }, canceledResult: () => throw const AccountPreferenceWriteCanceled());
    // A rejected edit releases the queue, while its caller still receives it.
    _storageTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  void _ensureCurrent(bool Function() isCurrent) {
    if (!isCurrent()) throw const AccountPreferenceWriteCanceled();
  }

  List<QuickCaptureTemplate> _snapshot(SharedPreferences prefs) =>
      _storageLoaded
      ? List.of(_customTemplates)
      : List.of(_decode(prefs.getString(_storageKey)));

  Future<void> _persist(
    AccountPreferenceTransaction transaction,
    List<QuickCaptureTemplate> snapshot,
  ) async {
    await transaction.setString(
      _storageKey,
      json.encode(snapshot.map((item) => item.toJson()).toList()),
    );
  }

  void _publish(List<QuickCaptureTemplate> snapshot) {
    _customTemplates
      ..clear()
      ..addAll(snapshot);
    _storageLoaded = true;
  }

  void _notifyLocalMutationPersisted() {
    try {
      onLocalMutationPersisted?.call();
    } catch (e, st) {
      debugPrint(
        '[QuickCaptureTemplateProvider] local mutation callback failed: $e\n$st',
      );
    }
  }

  List<QuickCaptureTemplate> _decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = json.decode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((item) {
            return QuickCaptureTemplate.fromJson(
              Map<String, dynamic>.from(item),
            );
          })
          .where((item) => !item.builtIn)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _storageGeneration++;
    super.dispose();
  }
}
