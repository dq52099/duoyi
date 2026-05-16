import 'achievements.dart';

class AchievementSnapshot {
  final String id;
  final bool unlocked;
  final int current;
  final int? target;
  final DateTime? unlockedAt;

  const AchievementSnapshot({
    required this.id,
    required this.unlocked,
    required this.current,
    this.target,
    this.unlockedAt,
  });

  double get progress {
    final t = target;
    if (t == null || t <= 0) return unlocked ? 1.0 : 0.0;
    return (current / t).clamp(0.0, 1.0);
  }
}

class AchievementEngine {
  AchievementEngine({List<Achievement> rules = Achievements.all})
    : _rules = rules;

  final List<Achievement> _rules;

  List<AchievementSnapshot> evaluate({
    required AchievementContext context,
    required Map<String, DateTime> previouslyUnlocked,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    return [
      for (final rule in _rules)
        _evaluateOne(rule, context, previouslyUnlocked[rule.id], at),
    ];
  }

  AchievementSnapshot _evaluateOne(
    Achievement rule,
    AchievementContext context,
    DateTime? previousUnlockedAt,
    DateTime now,
  ) {
    final unlockedByRule = rule.unlocked(context);
    final unlocked = previousUnlockedAt != null || unlockedByRule;
    final current = rule.current?.call(context) ?? (unlocked ? 1 : 0);
    return AchievementSnapshot(
      id: rule.id,
      unlocked: unlocked,
      current: current,
      target: rule.target,
      unlockedAt: previousUnlockedAt ?? (unlockedByRule ? now : null),
    );
  }
}
