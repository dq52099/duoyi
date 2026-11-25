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
    final host = File(
      'lib/widgets/achievement_feedback_host.dart',
    ).readAsStringSync();
    expect(main, contains('AchievementFeedbackHost(child: child!)'));
    expect(host, contains('provider.addListener(_receive)'));
    expect(host, contains('_provider?.removeListener(_receive)'));
    expect(host, contains('AchievementUiCopy.unlockMessage(badge)'));
    expect(host, contains('_provider?.storageGeneration == _generation'));
    expect(
      host,
      contains('AccountLocalDataCleaner.accountDataGenerationListenable'),
    );
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
