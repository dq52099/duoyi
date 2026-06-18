import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('成就解锁会产生应用内可见反馈', () {
    final provider = File(
      'lib/providers/achievement_provider.dart',
    ).readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();

    expect(provider, contains('_pendingUnlockedFeedback'));
    expect(provider, contains('takeUnlockedFeedback'));
    expect(provider, contains('_pendingUnlockedFeedback.addAll('));
    expect(provider, contains('newlyUnlocked.where('));
    expect(
      provider,
      contains('!_notifiedAchievementIds.contains(achievement.id)'),
    );
    expect(main, contains('addListener(_showAchievementFeedback)'));
    expect(main, contains('removeListener(_showAchievementFeedback)'));
    expect(main, contains('ScaffoldMessenger.maybeOf(context)'));
    expect(main, contains('解锁成就：'));
  });

  test('成就通知重启后不会重复进入通知栏和小红点', () {
    final provider = File(
      'lib/providers/achievement_provider.dart',
    ).readAsStringSync();
    final notifications = File(
      'lib/providers/notification_service.dart',
    ).readAsStringSync();

    expect(provider, contains('duoyi_achievements_notified'));
    expect(provider, contains('await loadFromStorage();'));
    expect(provider, contains('..addAll(_unlockedAt.keys)'));
    expect(notifications, contains('relatedId == achievement.id'));
    expect(notifications, contains("item.title.startsWith('成就解锁：')"));
  });
}
