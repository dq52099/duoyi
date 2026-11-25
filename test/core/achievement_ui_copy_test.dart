import 'package:duoyi/core/achievement_ui_copy.dart';
import 'package:duoyi/core/achievements.dart';
import 'package:duoyi/core/domain_event_bus.dart';
import 'package:duoyi/core/growth_levels.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/productivity_challenges.dart';
import 'package:duoyi/core/virtual_rewards.dart';
import 'package:duoyi/providers/achievement_provider.dart';
import 'package:flutter_test/flutter_test.dart';

final _awardedAt = DateTime.utc(2026, 10, 15, 12);

bool _containsHan(String value) => value.runes.any(
  (rune) =>
      (rune >= 0x3400 && rune <= 0x4DBF) ||
      (rune >= 0x4E00 && rune <= 0x9FFF) ||
      (rune >= 0xF900 && rune <= 0xFAFF) ||
      (rune >= 0x20000 && rune <= 0x3134F),
);

AchievementContext _emptyAchievementContext() => const AchievementContext(
  totalTodos: 0,
  completedTodos: 0,
  longestHabitStreak: 0,
  habitCount: 0,
  focusMinutes: 0,
  focusSessions: 0,
  diaryStreak: 0,
  diaryCount: 0,
  goalsTotal: 0,
  goalsAchieved: 0,
  anniversaries: 0,
  courses: 0,
  notes: 0,
);

RewardLedgerEntry _entryFromGrant(RewardGrant grant) => RewardLedgerEntry(
  id: grant.id,
  title: grant.title,
  coins: grant.coins,
  reason: grant.reason,
  awardedAt: _awardedAt,
);

List<(Achievement, RewardLedgerEntry)> _achievementEntries() => [
  for (final badge in Achievements.all)
    (
      badge,
      _entryFromGrant(
        VirtualRewardRules.forAchievement(
          id: badge.id,
          title: badge.title,
          description: badge.description,
        ),
      ),
    ),
];

List<(ProductivityChallenge, RewardLedgerEntry)> _challengeEntries() {
  final challenges = ProductivityChallenges.build(_emptyAchievementContext());
  return [
    for (final challenge in challenges)
      (
        challenge,
        _entryFromGrant(
          ProductivityChallenges.rewardGrant(
            challenge,
            now: DateTime(2026, 10, 15, 12),
          ),
        ),
      ),
  ];
}

List<(String, RewardLedgerEntry)> _eventEntries() {
  final events = <(String, DomainEvent)>[
    (
      'todo',
      DomainEvent(type: DomainEventType.todoCompleted, objectId: 'todo-1'),
    ),
    (
      'habit',
      DomainEvent(
        type: DomainEventType.habitCheckedIn,
        objectId: 'habit-1',
        occurredAt: _awardedAt,
        metadata: const {'date': '2026-10-15', 'count': 1},
      ),
    ),
    (
      'focus',
      DomainEvent(
        type: DomainEventType.pomodoroCompleted,
        objectId: 'focus-1',
        metadata: const {'durationSeconds': 1500},
      ),
    ),
    (
      'goal',
      DomainEvent(type: DomainEventType.goalAchieved, objectId: 'goal-1'),
    ),
    (
      'milestone',
      DomainEvent(
        type: DomainEventType.goalMilestoneCompleted,
        objectId: 'milestone-1',
      ),
    ),
    (
      'diary',
      DomainEvent(type: DomainEventType.diaryWritten, objectId: 'diary-1'),
    ),
  ];

  return [
    for (final (kind, event) in events)
      (kind, _entryFromGrant(VirtualRewardRules.forEvent(event)!)),
  ];
}

List<RewardLedgerEntry> _literalLedgerEntries() => [
  RewardLedgerEntry(
    id: 'challenge:unknown_challenge:2026-10-15',
    title: '未知挑战 literal title',
    coins: 5,
    reason: '未知挑战 literal reason',
    awardedAt: _awardedAt,
  ),
  RewardLedgerEntry(
    id: 'custom:imported-7',
    title: '自定义奖励 custom title',
    coins: 8,
    reason: '用户填写的 custom reason',
    awardedAt: _awardedAt,
  ),
  RewardLedgerEntry(
    id: 'spend:123456',
    title: '兑换自定义奖励',
    coins: -12,
    reason: '购买时填写的说明 literal',
    awardedAt: _awardedAt,
  ),
];

List<RewardLedgerEntry> _allLedgerEntries() => [
  ..._achievementEntries().map((pair) => pair.$2),
  ..._challengeEntries().map((pair) => pair.$2),
  ..._eventEntries().map((pair) => pair.$2),
  ..._literalLedgerEntries(),
];

void main() {
  setUp(() => I18n.setLocale(AppLocale.zh));
  tearDown(() => I18n.setLocale(AppLocale.zh));

  test(
    'English badge, challenge, and growth level catalog copy is translated',
    () {
      expect(Achievements.all, hasLength(19));
      for (final badge in Achievements.all) {
        final title = AchievementUiCopy.badgeTitle(badge, locale: AppLocale.en);
        final description = AchievementUiCopy.badgeDescription(
          badge,
          locale: AppLocale.en,
        );
        expect(title, isNotEmpty, reason: badge.id);
        expect(_containsHan(title), isFalse, reason: badge.id);
        expect(title, isNot(badge.title), reason: badge.id);
        expect(description, isNotEmpty, reason: badge.id);
        expect(_containsHan(description), isFalse, reason: badge.id);
        expect(description, isNot(badge.description), reason: badge.id);
      }

      final challenges = ProductivityChallenges.build(
        _emptyAchievementContext(),
      );
      expect(challenges, hasLength(9));
      I18n.setLocale(AppLocale.en);
      for (final challenge in challenges) {
        final title = AchievementUiCopy.challengeTitle(challenge);
        final description = AchievementUiCopy.challengeDescription(challenge);
        expect(title, isNotEmpty, reason: challenge.id);
        expect(_containsHan(title), isFalse, reason: challenge.id);
        expect(title, isNot(challenge.title), reason: challenge.id);
        expect(description, isNotEmpty, reason: challenge.id);
        expect(_containsHan(description), isFalse, reason: challenge.id);
        expect(description, isNot(challenge.description), reason: challenge.id);
      }

      final levels = GrowthLevels.thresholds
          .map(GrowthLevels.fromLifetimeCoins)
          .toList();
      expect(levels, hasLength(15));
      for (final level in levels) {
        final title = AchievementUiCopy.levelTitle(level);
        expect(title, isNotEmpty, reason: 'level ${level.level}');
        expect(_containsHan(title), isFalse, reason: 'level ${level.level}');
        expect(title, isNot(level.title), reason: 'level ${level.level}');
      }
    },
  );

  test(
    'challenge periods and every achievement unlock message follow locale',
    () {
      final challenges = ProductivityChallenges.build(
        _emptyAchievementContext(),
      );
      for (final challenge in challenges) {
        final periodZh = challenge.period == ProductivityChallengePeriod.daily
            ? '今日挑战'
            : '本周挑战';
        final periodEn = challenge.period == ProductivityChallengePeriod.daily
            ? 'Today'
            : 'This week';
        I18n.setLocale(AppLocale.zh);
        expect(AchievementUiCopy.challengePeriod(challenge), periodZh);
        I18n.setLocale(AppLocale.en);
        expect(AchievementUiCopy.challengePeriod(challenge), periodEn);
      }

      for (final badge in Achievements.all) {
        I18n.setLocale(AppLocale.zh);
        expect(
          AchievementUiCopy.unlockMessage(badge),
          '解锁成就：${badge.title}',
          reason: badge.id,
        );
        I18n.setLocale(AppLocale.en);
        expect(
          AchievementUiCopy.unlockMessage(badge),
          'Achievement unlocked: ${AchievementUiCopy.badgeTitle(badge, locale: AppLocale.en)}',
          reason: badge.id,
        );
      }
    },
  );

  test('stable ledger IDs translate achievement, challenge, and event rewards', () {
    for (final (badge, entry) in _achievementEntries()) {
      expect(entry.id, 'achievement:${badge.id}');
      I18n.setLocale(AppLocale.zh);
      expect(AchievementUiCopy.ledgerTitle(entry), entry.title);
      expect(AchievementUiCopy.ledgerReason(entry), badge.description);
      I18n.setLocale(AppLocale.en);
      expect(
        AchievementUiCopy.ledgerTitle(entry),
        'Achievement unlocked: ${AchievementUiCopy.badgeTitle(badge, locale: AppLocale.en)}',
        reason: entry.id,
      );
      expect(
        AchievementUiCopy.ledgerReason(entry),
        AchievementUiCopy.badgeDescription(badge, locale: AppLocale.en),
        reason: entry.id,
      );
    }

    for (final (challenge, entry) in _challengeEntries()) {
      final date = challenge.period == ProductivityChallengePeriod.daily
          ? '2026-10-15'
          : '2026-10-12';
      expect(entry.id, 'challenge:${challenge.id}:$date');
      I18n.setLocale(AppLocale.zh);
      expect(AchievementUiCopy.ledgerTitle(entry), entry.title);
      expect(AchievementUiCopy.ledgerReason(entry), entry.reason);
      I18n.setLocale(AppLocale.en);
      expect(
        AchievementUiCopy.ledgerTitle(entry),
        'Challenge completed: ${AchievementUiCopy.challengeTitle(challenge)}',
        reason: entry.id,
      );
      expect(
        AchievementUiCopy.ledgerReason(entry),
        '${challenge.period == ProductivityChallengePeriod.daily ? 'Today’s challenge' : 'Weekly challenge'} · $date',
        reason: entry.id,
      );
    }

    const englishEventCopy = <String, (String, String)>{
      'todo': ('Task completed', 'Task completion reward'),
      'habit': ('Habit check-in', 'Habit check-in reward'),
      'focus': ('Focus completed', 'Focus time reward'),
      'goal': ('Goal achieved', 'Goal achievement reward'),
      'milestone': ('Milestone completed', 'Goal milestone reward'),
      'diary': ('Diary entry written', 'Diary entry reward'),
    };
    expect(englishEventCopy, hasLength(6));
    for (final (kind, entry) in _eventEntries()) {
      expect(entry.id, startsWith('event:$kind:'));
      expect(entry.id.split(':')[2], isNotEmpty);
      I18n.setLocale(AppLocale.zh);
      expect(AchievementUiCopy.ledgerTitle(entry), entry.title);
      expect(AchievementUiCopy.ledgerReason(entry), entry.reason);
      I18n.setLocale(AppLocale.en);
      expect(AchievementUiCopy.ledgerTitle(entry), englishEventCopy[kind]!.$1);
      expect(AchievementUiCopy.ledgerReason(entry), englishEventCopy[kind]!.$2);
    }
  });

  test(
    'unknown, custom, and spend ledger copy stays literal in either locale',
    () {
      for (final entry in _literalLedgerEntries()) {
        for (final locale in AppLocale.values) {
          I18n.setLocale(locale);
          expect(
            AchievementUiCopy.ledgerTitle(entry),
            entry.title,
            reason: entry.id,
          );
          expect(
            AchievementUiCopy.ledgerReason(entry),
            entry.reason,
            reason: entry.id,
          );
        }
      }
    },
  );

  test('localizing ledger display does not change serialized entries', () {
    final entries = _allLedgerEntries();
    final serializedBefore = [for (final entry in entries) entry.toJson()];

    for (final locale in AppLocale.values) {
      I18n.setLocale(locale);
      for (final entry in entries) {
        AchievementUiCopy.ledgerTitle(entry);
        AchievementUiCopy.ledgerReason(entry);
      }
      expect([for (final entry in entries) entry.toJson()], serializedBefore);
    }
  });
}
