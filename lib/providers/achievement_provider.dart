import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/achievement_engine.dart';
import '../core/account_preference_writes.dart';
import '../core/achievements.dart';
import '../core/domain_event_bus.dart';
import '../core/growth_levels.dart';
import '../core/productivity_challenges.dart';
import '../core/virtual_rewards.dart';
import '../services/account_local_data_cleaner.dart';
import 'notification_service.dart';

class RewardLedgerEntry {
  final String id;
  final String title;
  final int coins;
  final String reason;
  final DateTime awardedAt;

  const RewardLedgerEntry({
    required this.id,
    required this.title,
    required this.coins,
    required this.reason,
    required this.awardedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'coins': coins,
    'reason': reason,
    'awardedAt': awardedAt.toIso8601String(),
  };

  factory RewardLedgerEntry.fromJson(Map<String, dynamic> json) {
    return RewardLedgerEntry(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      coins: (json['coins'] as num?)?.toInt() ?? 0,
      reason: json['reason']?.toString() ?? '',
      awardedAt:
          DateTime.tryParse(json['awardedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

/// One debit tied to the same preference transaction as its purchased item.
class CoinPurchase {
  CoinPurchase._(this._provider, this.isCurrent);

  final AchievementProvider _provider;
  final bool Function() isCurrent;
  AccountPreferenceTransaction? _transaction;
  RewardLedgerEntry? _receipt;
  String? _previousUpdatedAt;

  bool get committed => _transaction?.isCommitted == true;

  void ensureCurrent() {
    if (!isCurrent()) throw const AccountPreferenceWriteCanceled();
  }

  Future<bool> debit(
    AccountPreferenceTransaction transaction, {
    required int coins,
    required String title,
    required String reason,
  }) async {
    ensureCurrent();
    if (_receipt != null) throw StateError('Purchase already debited');
    if (coins < 0 || _provider._coinBalance < coins) return false;
    if (coins == 0) return true;
    _transaction = transaction;
    _previousUpdatedAt = _provider._rewardsUpdatedAt;
    final now = DateTime.now();
    final receipt = RewardLedgerEntry(
      id: 'spend:${now.microsecondsSinceEpoch}:${++_provider._receiptSequence}',
      title: title,
      coins: -coins,
      reason: reason,
      awardedAt: now,
    );
    _receipt = receipt;
    _provider._coinBalance -= coins;
    // Keep old entries until commit, so a failed debit cannot discard history.
    _provider._rewardLedger.insert(0, receipt);
    await _provider._writeRewards(transaction);
    ensureCurrent();
    return true;
  }

  void _refund() {
    final receipt = _receipt;
    if (receipt == null) return;
    _provider._coinBalance -= receipt.coins;
    _provider._rewardLedger.removeWhere((entry) => entry.id == receipt.id);
    _provider._rewardsUpdatedAt = _previousUpdatedAt!;
  }
}

class AchievementProvider extends ChangeNotifier {
  static const _storageKey = 'duoyi_achievements_unlocked';
  static const _rewardStorageKey = 'duoyi_virtual_rewards';
  static const _notifiedStorageKey = 'duoyi_achievements_notified';

  final AchievementEngine _engine;
  final DomainEventBus _bus;
  StreamSubscription<DomainEvent>? _eventSub;
  NotificationService? _notificationService;
  AchievementContext? _context;

  final Map<String, DateTime> _unlockedAt = {};
  final List<Achievement> _pendingUnlockedFeedback = <Achievement>[];
  final Set<String> _notifiedAchievementIds = <String>{};
  final Set<String> _rewardGrantIds = <String>{};
  final List<RewardLedgerEntry> _rewardLedger = <RewardLedgerEntry>[];
  List<AchievementSnapshot> _snapshots = const <AchievementSnapshot>[];
  DateTime? _lastEventAt;
  int _coinBalance = 0;
  int _lifetimeCoins = 0;
  int _persistedRevision = 0;
  String _rewardsUpdatedAt = '';
  bool _serverConfirmedRewardsChangePending = false;
  bool _storageLoaded = false;
  // 账号切换 / 登录后会先清空本地成就状态，再由云端 `achievement_states`
  // 回填 `_unlockedAt`。在回填完成前，任何对刚同步数据的成就重算都会把早已
  // 解锁（且用户已读）的成就误判为“新解锁”，从而重复弹出解锁提示。
  // 该开关在切号期间抑制解锁反馈（Toast + 系统通知），待基线恢复后再放开。
  bool _unlockFeedbackSuppressed = false;
  // 每次切号 / 登录抑制都会自增，用于让上一轮的安全兜底定时器失效：
  // 30s 兜底定时器捕获抑制时的代次，仅当代次未变时才放开，避免二次切号
  // 仍在抑制窗口内时被旧定时器提前恢复。
  int _unlockSuppressionGeneration = 0;
  Future<void>? _storageLoadFuture;
  int _storageGeneration = 0;
  int _receiptSequence = 0;
  Future<void> _rewardWriteTail = Future<void>.value();
  AccountPreferenceWriteToken? _activeRewardWriteToken;
  int get storageGeneration => _storageGeneration;

  Future<T> _enqueueRewardChange<T>(
    Future<T> Function(
      SharedPreferences prefs,
      AccountPreferenceWriteToken token,
    )
    operation, {
    required T Function() canceledResult,
  }) {
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    return AccountPreferenceWrites.runResult<T>((token) {
      bool isCurrent() =>
          generation == _storageGeneration &&
          AccountLocalDataCleaner.isCurrentAccountDataGeneration(
            accountGeneration,
          ) &&
          token.isCurrent;
      final pending = _rewardWriteTail.then<T>((_) async {
        if (!isCurrent()) return canceledResult();
        final prefs = await SharedPreferences.getInstance();
        if (!isCurrent()) return canceledResult();
        _activeRewardWriteToken = token;
        try {
          return await operation(prefs, token);
        } on AccountPreferenceWriteCanceled {
          return canceledResult();
        } finally {
          _activeRewardWriteToken = null;
        }
      });
      _rewardWriteTail = pending.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {},
      );
      return pending;
    }, canceledResult: canceledResult);
  }

  /// Holds reward mutation/hydration until the item transaction also settles.
  Future<bool> runCoinPurchase(
    Future<bool> Function(CoinPurchase purchase) operation, {
    bool Function()? isAuthorized,
  }) {
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    bool belongsToAccount() =>
        generation == _storageGeneration &&
        AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          accountGeneration,
        );
    return _enqueueRewardChange<bool>((prefs, token) async {
      final purchase = CoinPurchase._(
        this,
        () =>
            belongsToAccount() &&
            token.isCurrent &&
            (isAuthorized?.call() ?? true),
      );
      if (!purchase.isCurrent()) return false;
      try {
        return await operation(purchase);
      } on AccountPreferenceWriteCanceled {
        return purchase.committed;
      } catch (_) {
        // A post-commit observer failure must never make an unlocked item free.
        if (purchase.committed) return true;
        rethrow;
      } finally {
        if (belongsToAccount() && purchase._receipt != null) {
          if (purchase.committed) {
            _trimRewardLedger();
            _persistedRevision++;
            notifyListeners();
          } else {
            // Token invalidation can be an aborted boundary in the same account.
            // The shared transaction has already restored disk before this runs.
            purchase._refund();
            notifyListeners();
          }
        }
      }
    }, canceledResult: () => false);
  }

  AchievementProvider({AchievementEngine? engine, DomainEventBus? bus})
    : _engine = engine ?? AchievementEngine(),
      _bus = bus ?? DomainEventBus.instance;

  List<AchievementSnapshot> get snapshots =>
      List<AchievementSnapshot>.unmodifiable(_snapshots);
  List<ProductivityChallenge> get challenges => _context == null
      ? const <ProductivityChallenge>[]
      : ProductivityChallenges.build(_context!);
  Map<String, DateTime> get unlockedAt =>
      Map<String, DateTime>.unmodifiable(_unlockedAt);
  DateTime? get lastEventAt => _lastEventAt;
  int get coinBalance => _coinBalance;
  int get lifetimeCoins => _lifetimeCoins;
  int get persistedRevision => _persistedRevision;
  GrowthLevel get growthLevel => GrowthLevels.fromLifetimeCoins(_lifetimeCoins);
  List<RewardLedgerEntry> get rewardLedger =>
      List<RewardLedgerEntry>.unmodifiable(_rewardLedger);

  bool consumeServerConfirmedRewardsChange() {
    final value = _serverConfirmedRewardsChangePending;
    _serverConfirmedRewardsChangePending = false;
    return value;
  }

  int get unlockedCount => _snapshots.where((s) => s.unlocked).length;
  int get totalCount => Achievements.all.length;

  List<Achievement> takeUnlockedFeedback() {
    if (_pendingUnlockedFeedback.isEmpty) return const <Achievement>[];
    final next = List<Achievement>.unmodifiable(_pendingUnlockedFeedback);
    _pendingUnlockedFeedback.clear();
    return next;
  }

  /// 切号 / 登录开始时调用：在云端成就基线回填前抑制解锁反馈，
  /// 避免把早已解锁的成就当成“新解锁”重复弹窗。
  ///
  /// 返回本轮抑制的代次，调用方可把它传给 [resumeUnlockFeedback] 作为兜底，
  /// 确保只有“同一轮抑制”的延迟恢复才会生效。
  int suppressUnlockFeedback() {
    _unlockFeedbackSuppressed = true;
    _unlockSuppressionGeneration++;
    // 抑制窗口内已经误入队列的反馈先清掉，确保不会在恢复后补弹。
    _pendingUnlockedFeedback.clear();
    return _unlockSuppressionGeneration;
  }

  /// 云端基线回填完成（或切号流程结束）后调用，恢复正常解锁反馈。
  ///
  /// [generation] 非空时仅当它仍是最新一轮抑制才放开——这样上一轮切号的
  /// 安全兜底定时器不会误恢复正处于抑制窗口的新一轮切号。云端基线回填的
  /// 即时恢复不传 [generation]，无条件放开。
  ///
  /// 恢复前会把当前所有已解锁成就（`_unlockedAt.keys`）标记为"已通知"：
  /// 这些成就是在抑制窗口内 / 云端基线回填期间记录下来的，属于"早已解锁"，
  /// 不应在恢复后被当成"新解锁"重复弹窗。真正的新解锁只可能发生在恢复之后。
  void resumeUnlockFeedback({int? generation}) {
    if (generation != null && generation != _unlockSuppressionGeneration) {
      return;
    }
    if (_unlockFeedbackSuppressed) {
      final beforeCount = _notifiedAchievementIds.length;
      _notifiedAchievementIds.addAll(_unlockedAt.keys);
      if (_notifiedAchievementIds.length != beforeCount) {
        // 持久化新增的"已通知"标记，避免下次 loadFromStorage 再次丢失。
        unawaited(_saveNotifiedAchievements());
      }
    }
    _unlockFeedbackSuppressed = false;
  }

  @visibleForTesting
  bool get unlockFeedbackSuppressed => _unlockFeedbackSuppressed;

  /// 当前抑制代次，供切号兜底定时器捕获后回传 [resumeUnlockFeedback]。
  int get unlockSuppressionGeneration => _unlockSuppressionGeneration;

  void attachNotificationService(NotificationService service) {
    _notificationService = service;
  }

  Future<bool> spendCoins({
    required int coins,
    required String title,
    required String reason,
  }) {
    if (coins <= 0) return Future<bool>.value(false);
    return runCoinPurchase((purchase) async {
      final prefs = await SharedPreferences.getInstance();
      final transaction = AccountPreferenceTransaction(
        prefs,
        purchase.isCurrent,
      );
      try {
        if (!await purchase.debit(
          transaction,
          coins: coins,
          title: title,
          reason: reason,
        )) {
          return false;
        }
        transaction.commit();
        return true;
      } catch (_) {
        await transaction.rollback(canceledBeforeCleanup: true);
        rethrow;
      }
    });
  }

  Future<void> applyRewardsSnapshot(Map<dynamic, dynamic> rewards) {
    final incoming = Map<String, dynamic>.from(rewards);
    return _enqueueRewardChange<void>((prefs, token) async {
      final generation = _storageGeneration;
      final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
      if (generation != _storageGeneration) return;
      if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(
        accountGeneration,
      )) {
        return;
      }
      if (_isIncomingRewardsOlder(incoming)) {
        debugPrint(
          '[reward-sync] skipped older snapshot incoming='
          '${_rewardsUpdatedAtOf(incoming)} current=$_rewardsUpdatedAt',
        );
        return;
      }
      final transaction = AccountPreferenceTransaction(
        prefs,
        () =>
            token.isCurrent &&
            generation == _storageGeneration &&
            AccountLocalDataCleaner.isCurrentAccountDataGeneration(
              accountGeneration,
            ),
      );
      try {
        await transaction.setString(_rewardStorageKey, jsonEncode(incoming));
        transaction.commit();
      } on AccountPreferenceWriteCanceled {
        await transaction.rollback(canceledBeforeCleanup: true);
        return;
      } catch (_) {
        await transaction.rollback(canceledBeforeCleanup: true);
        rethrow;
      }
      if (generation != _storageGeneration ||
          !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
            accountGeneration,
          )) {
        return;
      }
      final changed = _loadRewardsFromPrefs(prefs);
      if (!changed) return;
      _persistedRevision++;
      _serverConfirmedRewardsChangePending = true;
      debugPrint(
        '[reward-sync] applied server snapshot balance=$_coinBalance '
        'lifetime=$_lifetimeCoins revision=$_persistedRevision',
      );
      notifyListeners();
    }, canceledResult: () {});
  }

  Future<void> loadFromStorage() async {
    final existing = _storageLoadFuture;
    if (existing != null) return existing;
    final generation = _storageGeneration;
    final future = _enqueueRewardChange<void>(
      (_, _) => _loadFromStorageNow(generation),
      canceledResult: () {},
    );
    _storageLoadFuture = future;
    await future.whenComplete(() {
      if (_storageLoadFuture == future) {
        _storageLoadFuture = null;
      }
    });
  }

  void resetLocalState() {
    _storageGeneration++;
    _storageLoadFuture = null;
    _storageLoaded = false;
    _unlockedAt.clear();
    _pendingUnlockedFeedback.clear();
    _notifiedAchievementIds.clear();
    _rewardGrantIds.clear();
    _rewardLedger.clear();
    _snapshots = const <AchievementSnapshot>[];
    _lastEventAt = null;
    _coinBalance = 0;
    _lifetimeCoins = 0;
    _persistedRevision++;
    _rewardsUpdatedAt = '';
    _serverConfirmedRewardsChangePending = false;
    _context = null;
    notifyListeners();
  }

  Future<void> _loadFromStorageNow(int generation) async {
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final prefs = await SharedPreferences.getInstance();
    _activeRewardWriteToken?.ensureCurrent();
    if (generation != _storageGeneration) return;
    if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(
      accountGeneration,
    )) {
      return;
    }
    final beforeUnlocked = Map<String, DateTime>.of(_unlockedAt);
    final raw = prefs.getString(_storageKey);
    _unlockedAt.clear();
    if (raw != null && raw.isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        for (final entry in decoded.entries) {
          final parsed = DateTime.tryParse(entry.value.toString());
          if (parsed != null) _unlockedAt[entry.key.toString()] = parsed;
        }
      }
    }
    final previousNotifiedIds = Set<String>.from(_notifiedAchievementIds);
    final storedNotifiedIds = _normalizedAchievementIds(
      prefs.getStringList(_notifiedStorageKey) ?? const <String>[],
    );
    _notifiedAchievementIds
      ..clear()
      ..addAll(storedNotifiedIds)
      ..addAll(_unlockedAt.keys);
    if (_unlockFeedbackSuppressed) {
      _notifiedAchievementIds.addAll(previousNotifiedIds);
    }
    final shouldPersistNotified = !setEquals(
      storedNotifiedIds,
      _notifiedAchievementIds,
    );
    final unlockedChanged = !mapEquals(beforeUnlocked, _unlockedAt);
    final rewardsChanged = _loadRewardsFromPrefs(prefs);
    _storageLoaded = true;
    _subscribe();
    await _rebuildSnapshots(notify: false);
    if (shouldPersistNotified &&
        generation == _storageGeneration &&
        AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          accountGeneration,
        )) {
      await prefs.setStringList(
        _notifiedStorageKey,
        _sortedNotifiedAchievementIds(),
      );
    }
    if (unlockedChanged || rewardsChanged) notifyListeners();
  }

  Future<void> updateContext(
    AchievementContext context, {
    bool silentUnlockFeedback = false,
  }) async {
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    if (!_storageLoaded) {
      await loadFromStorage();
    }
    if (generation != _storageGeneration ||
        !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          accountGeneration,
        )) {
      return;
    }
    await _enqueueRewardChange<void>((_, _) async {
      _context = context;
      await _rebuildSnapshots(silentUnlockFeedback: silentUnlockFeedback);
    }, canceledResult: () {});
  }

  AchievementSnapshot snapshotFor(String achievementId) {
    return _snapshots.firstWhere(
      (s) => s.id == achievementId,
      orElse: () =>
          AchievementSnapshot(id: achievementId, unlocked: false, current: 0),
    );
  }

  void _subscribe() {
    _eventSub ??= _bus.events.listen((event) {
      unawaited(
        _enqueueRewardChange<void>((_, _) async {
          _lastEventAt = event.occurredAt;
          final grant = VirtualRewardRules.forEvent(event);
          var rewardsChanged = false;
          if (grant != null) {
            rewardsChanged = _award(grant, awardedAt: event.occurredAt);
          }
          await _rebuildSnapshots(rewardsChanged: rewardsChanged);
        }, canceledResult: () {}),
      );
    });
  }

  Future<void> _rebuildSnapshots({
    bool notify = true,
    bool rewardsChanged = false,
    bool silentUnlockFeedback = false,
  }) async {
    final context = _context;
    if (context == null) {
      _snapshots = [
        for (final achievement in Achievements.all)
          AchievementSnapshot(
            id: achievement.id,
            unlocked: _unlockedAt.containsKey(achievement.id),
            current: 0,
            target: achievement.target,
            unlockedAt: _unlockedAt[achievement.id],
          ),
      ];
      if (rewardsChanged) {
        await _saveRewards();
        _persistedRevision++;
      }
      if (notify) notifyListeners();
      return;
    }

    final previousIds = _unlockedAt.keys.toSet();
    final evaluated = _engine.evaluate(
      context: context,
      previouslyUnlocked: _unlockedAt,
    );
    final newlyUnlocked = <Achievement>[];
    for (final snapshot in evaluated) {
      if (!snapshot.unlocked || snapshot.unlockedAt == null) continue;
      if (!_unlockedAt.containsKey(snapshot.id)) {
        _unlockedAt[snapshot.id] = snapshot.unlockedAt!;
      }
      if (!previousIds.contains(snapshot.id)) {
        final rule = Achievements.all.firstWhere((a) => a.id == snapshot.id);
        newlyUnlocked.add(rule);
      }
    }
    _snapshots = evaluated
        .map(
          (snapshot) => AchievementSnapshot(
            id: snapshot.id,
            unlocked: snapshot.unlocked,
            current: snapshot.current,
            target: snapshot.target,
            unlockedAt: _unlockedAt[snapshot.id],
          ),
        )
        .toList(growable: false);
    var shouldSaveRewards = rewardsChanged;
    shouldSaveRewards |= _awardCompletedChallenges(context);

    // 切号 / 登录基线回填期间，强制走静默路径：仍记录解锁与发币，
    // 但不弹 Toast、不发系统通知，避免早已解锁的成就被重复“庆祝”。
    final silent = silentUnlockFeedback || _unlockFeedbackSuppressed;

    if (newlyUnlocked.isNotEmpty) {
      if (!silent) {
        // 与系统通知出口保持一致：已通知过的成就不再补弹应用内 Toast。
        _pendingUnlockedFeedback.addAll(
          newlyUnlocked.where(
            (achievement) => !_notifiedAchievementIds.contains(achievement.id),
          ),
        );
      }
      for (final achievement in newlyUnlocked) {
        shouldSaveRewards |= _award(
          VirtualRewardRules.forAchievement(
            id: achievement.id,
            title: achievement.title,
            description: achievement.description,
          ),
          awardedAt: _unlockedAt[achievement.id] ?? DateTime.now(),
        );
      }
    }

    final achievementIdsToMarkNotified = silent
        ? newlyUnlocked.map((achievement) => achievement.id).toList()
        : newlyUnlocked
              .map((achievement) => achievement.id)
              .where((id) => !_notifiedAchievementIds.contains(id))
              .toList(growable: false);
    final achievementsToNotify = silent
        ? const <Achievement>[]
        : newlyUnlocked
              .where(
                (achievement) =>
                    !_notifiedAchievementIds.contains(achievement.id),
              )
              .toList(growable: false);

    if (achievementIdsToMarkNotified.isNotEmpty) {
      _notifiedAchievementIds.addAll(achievementIdsToMarkNotified);
    }

    if (newlyUnlocked.isNotEmpty || shouldSaveRewards) {
      await _persistChangesThenNotify(
        saveAchievements: newlyUnlocked.isNotEmpty,
        saveRewards: shouldSaveRewards,
        notify: notify,
        achievementIdsToMarkNotified: achievementIdsToMarkNotified,
        achievementsToNotify: achievementsToNotify,
      );
      return;
    }

    if (notify) notifyListeners();
  }

  Future<void> _persistChangesThenNotify({
    required bool saveAchievements,
    required bool saveRewards,
    required bool notify,
    required List<String> achievementIdsToMarkNotified,
    required List<Achievement> achievementsToNotify,
  }) async {
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    if (saveAchievements) {
      await _save();
    }
    if (generation != _storageGeneration) {
      return;
    }
    if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(
      accountGeneration,
    )) {
      return;
    }
    if (saveRewards) {
      await _saveRewards();
    }
    if (generation != _storageGeneration) {
      return;
    }
    if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(
      accountGeneration,
    )) {
      return;
    }
    if (saveAchievements || saveRewards) {
      _persistedRevision++;
    }
    if (achievementIdsToMarkNotified.isNotEmpty) {
      _notifiedAchievementIds.addAll(achievementIdsToMarkNotified);
      await _saveNotifiedAchievements();
    }
    if (achievementsToNotify.isNotEmpty) {
      for (final achievement in achievementsToNotify) {
        _notificationService?.notifyAchievementUnlocked(achievement);
      }
    }
    if (notify) {
      notifyListeners();
    }
  }

  bool _awardCompletedChallenges(AchievementContext context) {
    var changed = false;
    for (final challenge in ProductivityChallenges.build(context)) {
      if (!challenge.completed) continue;
      changed |= _award(
        ProductivityChallenges.rewardGrant(challenge),
        awardedAt: DateTime.now(),
      );
    }
    return changed;
  }

  bool _award(RewardGrant grant, {required DateTime awardedAt}) {
    if (grant.coins <= 0 || _rewardGrantIds.contains(grant.id)) {
      return false;
    }
    _rewardGrantIds.add(grant.id);
    _coinBalance += grant.coins;
    _lifetimeCoins += grant.coins;
    _rewardLedger.insert(
      0,
      RewardLedgerEntry(
        id: grant.id,
        title: grant.title,
        coins: grant.coins,
        reason: grant.reason,
        awardedAt: awardedAt,
      ),
    );
    _trimRewardLedger();
    return true;
  }

  void _trimRewardLedger() {
    if (_rewardLedger.length > 50) {
      _rewardLedger.removeRange(50, _rewardLedger.length);
    }
  }

  bool _loadRewardsFromPrefs(SharedPreferences prefs) {
    final before = _rewardsSnapshotHash();
    final raw = prefs.getString(_rewardStorageKey);
    _coinBalance = 0;
    _lifetimeCoins = 0;
    _rewardsUpdatedAt = '';
    _rewardGrantIds.clear();
    _rewardLedger.clear();
    if (raw == null || raw.isEmpty) {
      return before != _rewardsSnapshotHash();
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return before != _rewardsSnapshotHash();
    _coinBalance = (decoded['balance'] as num?)?.toInt() ?? 0;
    _lifetimeCoins = (decoded['lifetime'] as num?)?.toInt() ?? _coinBalance;
    _rewardsUpdatedAt = _rewardsUpdatedAtOf(decoded);
    final grantIds = decoded['grantIds'];
    if (grantIds is List) {
      _rewardGrantIds.addAll(grantIds.map((id) => id.toString()));
    }
    final ledger = decoded['ledger'];
    if (ledger is List) {
      for (final item in ledger) {
        if (item is Map) {
          _rewardLedger.add(
            RewardLedgerEntry.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }
    return before != _rewardsSnapshotHash();
  }

  Future<void> _save() async {
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final data = jsonEncode(
      _unlockedAt.map(
        (id, unlockedAt) => MapEntry(id, unlockedAt.toIso8601String()),
      ),
    );
    final prefs = await SharedPreferences.getInstance();
    if (generation != _storageGeneration) {
      return;
    }
    if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(
      accountGeneration,
    )) {
      return;
    }
    await prefs.setString(_storageKey, data);
  }

  Future<void> _saveRewards() async {
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final prefs = await SharedPreferences.getInstance();
    bool isCurrent() =>
        _activeRewardWriteToken?.isCurrent == true &&
        generation == _storageGeneration &&
        AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          accountGeneration,
        );
    if (!isCurrent()) return;
    final transaction = AccountPreferenceTransaction(prefs, isCurrent);
    try {
      await _writeRewards(transaction);
      transaction.commit();
    } catch (_) {
      await transaction.rollback(canceledBeforeCleanup: true);
      rethrow;
    }
  }

  Future<void> _writeRewards(AccountPreferenceTransaction transaction) async {
    final updatedAt = DateTime.now().toUtc().toIso8601String();
    // Encode at execution time while the reward queue is held.
    final data = jsonEncode({
      'balance': _coinBalance,
      'lifetime': _lifetimeCoins,
      'grantIds': _rewardGrantIds.toList(growable: false),
      'ledger': _rewardLedger.take(50).map((entry) => entry.toJson()).toList(),
      'updatedAt': updatedAt,
    });
    await transaction.setString(_rewardStorageKey, data);
    _rewardsUpdatedAt = updatedAt;
  }

  Future<void> _saveNotifiedAchievements() async {
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final ids = _sortedNotifiedAchievementIds();
    final prefs = await SharedPreferences.getInstance();
    if (generation != _storageGeneration ||
        !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          accountGeneration,
        )) {
      return;
    }
    await prefs.setStringList(_notifiedStorageKey, ids);
  }

  Set<String> _normalizedAchievementIds(Iterable<String> ids) {
    return ids.map((id) => id.trim()).where((id) => id.isNotEmpty).toSet();
  }

  List<String> _sortedNotifiedAchievementIds() {
    return _notifiedAchievementIds.toList(growable: false)..sort();
  }

  bool _isIncomingRewardsOlder(Map<dynamic, dynamic> incoming) {
    final incomingUpdatedAt = _rewardsUpdatedAtOf(incoming);
    if (_rewardsUpdatedAt.isEmpty) return false;
    if (incomingUpdatedAt.isEmpty) return true;
    final incomingTime = DateTime.tryParse(incomingUpdatedAt);
    final currentTime = DateTime.tryParse(_rewardsUpdatedAt);
    if (incomingTime != null && currentTime != null) {
      return incomingTime.toUtc().isBefore(currentTime.toUtc());
    }
    return incomingUpdatedAt.compareTo(_rewardsUpdatedAt) < 0;
  }

  String _rewardsUpdatedAtOf(Map<dynamic, dynamic> data) {
    return data['updatedAt']?.toString() ??
        data['updated_at']?.toString() ??
        '';
  }

  Object _rewardsSnapshotHash() {
    var grantsHash = 0;
    for (final id in _rewardGrantIds) {
      grantsHash ^= id.hashCode;
    }
    var ledgerHash = 0;
    for (var i = 0; i < _rewardLedger.length; i++) {
      final entry = _rewardLedger[i];
      ledgerHash = Object.hash(
        ledgerHash,
        entry.id,
        entry.title,
        entry.coins,
        entry.reason,
        entry.awardedAt.millisecondsSinceEpoch,
      );
    }
    return (
      _coinBalance,
      _lifetimeCoins,
      _rewardsUpdatedAt,
      _rewardGrantIds.length,
      grantsHash,
      _rewardLedger.length,
      ledgerHash,
    );
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    super.dispose();
  }
}
