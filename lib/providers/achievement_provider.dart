import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/achievement_engine.dart';
import '../core/achievements.dart';
import '../core/domain_event_bus.dart';
import 'notification_service.dart';

class AchievementProvider extends ChangeNotifier {
  static const _storageKey = 'duoyi_achievements_unlocked';

  final AchievementEngine _engine;
  final DomainEventBus _bus;
  StreamSubscription<DomainEvent>? _eventSub;
  NotificationService? _notificationService;
  AchievementContext? _context;

  final Map<String, DateTime> _unlockedAt = {};
  List<AchievementSnapshot> _snapshots = const <AchievementSnapshot>[];
  DateTime? _lastEventAt;

  AchievementProvider({AchievementEngine? engine, DomainEventBus? bus})
    : _engine = engine ?? AchievementEngine(),
      _bus = bus ?? DomainEventBus.instance;

  List<AchievementSnapshot> get snapshots =>
      List<AchievementSnapshot>.unmodifiable(_snapshots);
  Map<String, DateTime> get unlockedAt =>
      Map<String, DateTime>.unmodifiable(_unlockedAt);
  DateTime? get lastEventAt => _lastEventAt;

  int get unlockedCount => _snapshots.where((s) => s.unlocked).length;
  int get totalCount => Achievements.all.length;

  void attachNotificationService(NotificationService service) {
    _notificationService = service;
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

    if (newlyUnlocked.isNotEmpty) {
      // ignore: discarded_futures
      _save();
      for (final achievement in newlyUnlocked) {
        _notificationService?.notifyAchievementUnlocked(achievement);
      }
    }
    if (notify) notifyListeners();
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

  @override
  void dispose() {
    _eventSub?.cancel();
    super.dispose();
  }
}
