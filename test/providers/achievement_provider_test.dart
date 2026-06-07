import 'dart:convert';

import 'package:duoyi/core/achievements.dart';
import 'package:duoyi/providers/achievement_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
    'loaded unlocked achievements do not re-enter feedback after restart',
    () async {
      final unlockedAt = DateTime(2026, 6, 1).toIso8601String();
      SharedPreferences.setMockInitialValues(<String, Object>{
        'duoyi_achievements_unlocked': json.encode({'first_todo': unlockedAt}),
        'duoyi_achievements_notified': <String>['first_todo'],
      });
      final provider = AchievementProvider();

      await provider.loadFromStorage();
      await provider.updateContext(
        const AchievementContext(
          totalTodos: 1,
          completedTodos: 1,
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
        ),
      );

      expect(provider.snapshotFor('first_todo').unlocked, isTrue);
      expect(provider.takeUnlockedFeedback(), isEmpty);
    },
  );

  test(
    'loadFromStorage clears stale rewards when account keys are removed',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'duoyi_achievements_unlocked': json.encode({
          'first_todo': '2026-06-01T00:00:00.000Z',
        }),
        'duoyi_achievements_notified': <String>['first_todo'],
        'duoyi_virtual_rewards': json.encode({
          'balance': 88,
          'lifetime': 120,
          'grantIds': <String>['admin-grant'],
          'ledger': <Map<String, Object>>[
            {
              'id': 'admin-grant',
              'title': 'Admin reward',
              'coins': 88,
              'reason': 'old account data',
              'awardedAt': '2026-06-01T00:00:00.000Z',
            },
          ],
          'updatedAt': '2026-06-01T00:00:00.000Z',
        }),
      });
      final provider = AchievementProvider();
      await provider.loadFromStorage();
      expect(provider.coinBalance, 88);
      expect(provider.unlockedAt, isNotEmpty);

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('duoyi_achievements_unlocked');
      await prefs.remove('duoyi_achievements_notified');
      await prefs.remove('duoyi_virtual_rewards');
      await provider.loadFromStorage();

      expect(provider.coinBalance, 0);
      expect(provider.lifetimeCoins, 0);
      expect(provider.rewardLedger, isEmpty);
      expect(provider.unlockedAt, isEmpty);
      provider.dispose();
    },
  );
}
