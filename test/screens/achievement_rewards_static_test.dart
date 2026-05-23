import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('成就系统提供时光币虚拟奖励闭环', () {
    final provider = File(
      'lib/providers/achievement_provider.dart',
    ).readAsStringSync();
    final screen = File(
      'lib/screens/achievements_screen.dart',
    ).readAsStringSync();
    final backup = File('lib/services/backup_service.dart').readAsStringSync();
    final cloudSync = File(
      'lib/providers/cloud_sync_provider.dart',
    ).readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();

    expect(provider, contains("import '../core/virtual_rewards.dart';"));
    expect(provider, contains("static const _rewardStorageKey"));
    expect(provider, contains('VirtualRewardRules.forEvent(event)'));
    expect(provider, contains('VirtualRewardRules.forAchievement('));
    expect(provider, contains('coinBalance'));
    expect(provider, contains('GrowthLevel get growthLevel'));
    expect(
      provider,
      contains('GrowthLevels.fromLifetimeCoins(_lifetimeCoins)'),
    );
    expect(provider, contains('rewardLedger'));
    expect(screen, contains('时光币'));
    expect(screen, contains("import '../core/growth_levels.dart';"));
    expect(screen, contains('growthLevel: provider.growthLevel'));
    expect(screen, contains('class _LevelCoinPanel'));
    expect(screen, contains(r"'Lv.${growthLevel.level}'"));
    expect(screen, contains('growthLevel.coinsRemaining'));
    expect(screen, contains('最近奖励'));
    expect(screen, contains('_RewardLedgerCard'));
    expect(screen, contains("tooltip: '成就分享图'"));
    expect(screen, contains('_AchievementShareDialog'));
    expect(screen, contains('_AchievementShareCard'));
    expect(screen, contains('_achievementShareMarkdown'));
    expect(screen, contains('RenderRepaintBoundary'));
    expect(screen, contains('ui.ImageByteFormat.png'));
    expect(screen, contains("package:share_plus/share_plus.dart"));
    expect(screen, contains('SharePlus.instance.share'));
    expect(screen, contains('ShareParams('));
    expect(screen, contains('XFile(file.path)'));
    expect(screen, contains('duoyi_achievement_'));
    expect(screen, contains('成就分享图已保存并打开系统分享面板'));
    expect(backup, contains("'duoyi_virtual_rewards'"));
    expect(cloudSync, contains("'duoyi_virtual_rewards': 'virtual_rewards'"));
    expect(main, contains('String _achievementPersistedSignature'));
    expect(main, contains('void markAchievementDirtyOnPersistedChange()'));
    expect(
      main,
      contains('achievementProvider.addListener(markAchievementDirtyOnPersistedChange)'),
    );
  });
}
