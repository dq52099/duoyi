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
  int _persistedRevision = 0;
  String _rewardsUpdatedAt = '';

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
    _persistedRevision++;
    notifyListeners();
    return true;
  }

  Future<void> applyRewardsSnapshot(Map<dynamic, dynamic> rewards) async {
    final prefs = await SharedPreferences.getInstance();
    final incoming = Map<String, dynamic>.from(rewards);
    if (_isIncomingRewardsOlder(incoming)) {
      debugPrint(
        '[reward-sync] skipped older snapshot incoming='
        '${_rewardsUpdatedAtOf(incoming)} current=$_rewardsUpdatedAt',
      );
      return;
    }
    await prefs.setString(_rewardStorageKey, jsonEncode(incoming));
    final changed = _loadRewardsFromPrefs(prefs);
    if (!changed) return;
    _persistedRevision++;
    debugPrint(
      '[reward-sync] applied server snapshot balance=$_coinBalance '
      'lifetime=$_lifetimeCoins revision=$_persistedRevision',
    );
    notifyListeners();
  }

  Future<void> loadFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final beforeUnlocked = jsonEncode(
      _unlockedAt.map(
        (id, unlockedAt) => MapEntry(id, unlockedAt.toIso8601String()),
      ),
    );
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
    final unlockedChanged =
        beforeUnlocked !=
        jsonEncode(
          _unlockedAt.map(
            (id, unlockedAt) => MapEntry(id, unlockedAt.toIso8601String()),
          ),
        );
    final rewardsChanged = _loadRewardsFromPrefs(prefs);
    _subscribe();
    _rebuildSnapshots(notify: false);
    if (unlockedChanged || rewardsChanged) notifyListeners();
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
      var rewardsChanged = false;
      if (grant != null) {
        rewardsChanged = _award(grant, awardedAt: event.occurredAt);
      }
      _rebuildSnapshots(rewardsChanged: rewardsChanged);
    });
  }

  void _rebuildSnapshots({bool notify = true, bool rewardsChanged = false}) {
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
    var shouldSaveRewards = rewardsChanged;
    shouldSaveRewards |= _awardCompletedChallenges(context);

    if (newlyUnlocked.isNotEmpty) {
      _pendingUnlockedFeedback.addAll(newlyUnlocked);
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

    if (newlyUnlocked.isNotEmpty || shouldSaveRewards) {
      unawaited(
        _persistChangesThenNotify(
          saveAchievements: newlyUnlocked.isNotEmpty,
          saveRewards: shouldSaveRewards,
          notify: notify,
          achievementsToNotify: newlyUnlocked,
        ),
      );
      return;
    }

    if (notify) notifyListeners();
  }

  Future<void> _persistChangesThenNotify({
    required bool saveAchievements,
    required bool saveRewards,
    required bool notify,
    required List<Achievement> achievementsToNotify,
  }) async {
    if (saveAchievements) {
      await _save();
    }
    if (saveRewards) {
      await _saveRewards();
    }
    if (saveAchievements || saveRewards) {
      _persistedRevision++;
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
    if (_rewardLedger.length > 50) {
      _rewardLedger.removeRange(50, _rewardLedger.length);
    }
    return true;
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
    _rewardsUpdatedAt = DateTime.now().toUtc().toIso8601String();
    await prefs.setString(
      _rewardStorageKey,
      jsonEncode({
        'balance': _coinBalance,
        'lifetime': _lifetimeCoins,
        'grantIds': _rewardGrantIds.toList(growable: false),
        'ledger': _rewardLedger.map((entry) => entry.toJson()).toList(),
        'updatedAt': _rewardsUpdatedAt,
      }),
    );
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

  String _rewardsSnapshotHash() {
    return jsonEncode({
      'balance': _coinBalance,
      'lifetime': _lifetimeCoins,
      'grantIds': _rewardGrantIds.toList(growable: false)..sort(),
      'ledger': _rewardLedger.map((entry) => entry.toJson()).toList(),
      'updatedAt': _rewardsUpdatedAt,
    });
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    super.dispose();
  }
}
