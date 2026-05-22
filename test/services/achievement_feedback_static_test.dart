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
    expect(
      provider,
      contains('_pendingUnlockedFeedback.addAll(newlyUnlocked)'),
    );
    expect(main, contains('addListener(_showAchievementFeedback)'));
    expect(main, contains('removeListener(_showAchievementFeedback)'));
    expect(main, contains('ScaffoldMessenger.maybeOf(context)'));
    expect(main, contains('解锁成就：'));
  });
}
