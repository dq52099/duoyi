import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/achievement_engine.dart';
import '../core/achievements.dart';
import '../core/domain_event_bus.dart';
import '../core/growth_levels.dart';
import '../core/productivity_challenges.dart';
import '../core/virtual_rewards.dart';
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

class AchievementProvider extends ChangeNotifier {
  static const _storageKey = 'duoyi_achievements_unlocked';
  static const _rewardStorageKey = 'duoyi_virtual_rewards';

  final AchievementEngine _engine;
  final DomainEventBus _bus;
  StreamSubscription<DomainEvent>? _eventSub;
  NotificationService? _notificationService;
  AchievementContext? _context;

  final Map<String, DateTime> _unlockedAt = {};
  final List<Achievement> _pendingUnlockedFeedback = <Achievement>[];
  final Set<String> _rewardGrantIds = <String>{};
  final List<RewardLedgerEntry> _rewardLedger = <RewardLedgerEntry>[];
  List<AchievementSnapshot> _snapshots = const <AchievementSnapshot>[];
  DateTime? _lastEventAt;
  int _coinBalance = 0;
  int _lifetimeCoins = 0;

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
  GrowthLevel get growthLevel => GrowthLevels.fromLifetimeCoins(_lifetimeCoins);
  List<RewardLedgerEntry> get rewardLedger =>
      List<RewardLedgerEntry>.unmodifiable(_rewardLedger);

  int get unlockedCount => _snapshots.where((s) => s.unlocked).length;
  int get totalCount => Achievements.all.length;

  List<Achievement> takeUnlockedFeedback() {
    if (_pendingUnlockedFeedback.isEmpty) return const <Achievement>[];
    final next = List<Achievement>.unmodifiable(_pendingUnlockedFeedback);
    _pendingUnlockedFeedback.clear();
    return next;
  }

  void attachNotificationService(NotificationService service) {
    _notificationService = service;
  }

  Future<bool> spendCoins({
    required int coins,
    required String title,
    required String reason,
  }) async {
    if (coins <= 0 || _coinBalance < coins) return false;
    _coinBalance -= coins;
    _rewardLedger.insert(
      0,
      RewardLedgerEntry(
        id: 'spend:${DateTime.now().microsecondsSinceEpoch}',
        title: title,
        coins: -coins,
        reason: reason,
        awardedAt: DateTime.now(),
      ),
    );
    if (_rewardLedger.length > 50) {
      _rewardLedger.removeRange(50, _rewardLedger.length);
    }
    await _saveRewards();
    notifyListeners();
    return true;
  }

  Future<void> loadFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
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
    _loadRewardsFromPrefs(prefs);
    _subscribe();
    _rebuildSnapshots(notify: false);
    notifyListeners();
  }

  void updateContext(AchievementContext context) {
    _context = context;
    _rebuildSnapshots();
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
      _lastEventAt = event.occurredAt;
      final grant = VirtualRewardRules.forEvent(event);
      if (grant != null) {
        _award(grant, awardedAt: event.occurredAt, notify: false);
      }
      _rebuildSnapshots();
    });
  }

  void _rebuildSnapshots({bool notify = true}) {
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
    _awardCompletedChallenges(context);

    if (newlyUnlocked.isNotEmpty) {
      _pendingUnlockedFeedback.addAll(newlyUnlocked);
      for (final achievement in newlyUnlocked) {
        _award(
          VirtualRewardRules.forAchievement(
            id: achievement.id,
            title: achievement.title,
            description: achievement.description,
          ),
          awardedAt: _unlockedAt[achievement.id] ?? DateTime.now(),
          notify: false,
        );
      }
      // ignore: discarded_futures
      _save();
      for (final achievement in newlyUnlocked) {
        _notificationService?.notifyAchievementUnlocked(achievement);
      }
    }
    if (notify) notifyListeners();
  }

  void _awardCompletedChallenges(AchievementContext context) {
    for (final challenge in ProductivityChallenges.build(context)) {
      if (!challenge.completed) continue;
      _award(
        ProductivityChallenges.rewardGrant(challenge),
        awardedAt: DateTime.now(),
        notify: false,
      );
    }
  }

  void _award(
    RewardGrant grant, {
    required DateTime awardedAt,
    bool notify = true,
  }) {
    if (grant.coins <= 0 || _rewardGrantIds.contains(grant.id)) return;
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
    if (_rewardLedger.length > 50) {
      _rewardLedger.removeRange(50, _rewardLedger.length);
    }
    // ignore: discarded_futures
    _saveRewards();
    if (notify) notifyListeners();
  }

  void _loadRewardsFromPrefs(SharedPreferences prefs) {
    final raw = prefs.getString(_rewardStorageKey);
    _coinBalance = 0;
    _lifetimeCoins = 0;
    _rewardGrantIds.clear();
    _rewardLedger.clear();
    if (raw == null || raw.isEmpty) return;
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return;
    _coinBalance = (decoded['balance'] as num?)?.toInt() ?? 0;
    _lifetimeCoins = (decoded['lifetime'] as num?)?.toInt() ?? _coinBalance;
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
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode(
        _unlockedAt.map(
          (id, unlockedAt) => MapEntry(id, unlockedAt.toIso8601String()),
        ),
      ),
    );
  }

  Future<void> _saveRewards() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _rewardStorageKey,
      jsonEncode({
        'balance': _coinBalance,
        'lifetime': _lifetimeCoins,
        'grantIds': _rewardGrantIds.toList(growable: false),
        'ledger': _rewardLedger.map((entry) => entry.toJson()).toList(),
      }),
    );
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    super.dispose();
  }
}
