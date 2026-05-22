import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('主题页接入时光币奖励商店和主题解锁', () {
    final themeProvider = File(
      'lib/providers/theme_provider.dart',
    ).readAsStringSync();
    final themeScreen = File(
      'lib/screens/theme_picker_screen.dart',
    ).readAsStringSync();
    final achievementProvider = File(
      'lib/providers/achievement_provider.dart',
    ).readAsStringSync();
    final backup = File('lib/services/backup_service.dart').readAsStringSync();
    final cloudSync = File(
      'lib/providers/cloud_sync_provider.dart',
    ).readAsStringSync();

    expect(themeProvider, contains('premiumBrandCost'));
    expect(themeProvider, contains('theme_unlocked_brands'));
    expect(themeProvider, contains('theme_shop_state'));
    expect(themeProvider, contains('isBrandUnlocked'));
    expect(themeProvider, contains('unlockBrand'));
    expect(themeProvider, contains('brandCost'));
    expect(themeProvider, contains('FocusBackdropReward'));
    expect(themeProvider, contains('focusBackdropRewards'));
    expect(themeProvider, contains('isFocusBackdropUnlocked'));
    expect(themeProvider, contains('unlockFocusBackdrop'));
    expect(themeProvider, contains('setFocusBackdrop'));
    expect(themeProvider, contains('activeFocusBackdropId'));
    expect(themeProvider, contains('unlockedFocusBackdropIds'));
    expect(themeProvider, contains('AvatarFrameReward'));
    expect(themeProvider, contains('avatarFrameRewards'));
    expect(themeProvider, contains('isAvatarFrameUnlocked'));
    expect(themeProvider, contains('unlockAvatarFrame'));
    expect(themeProvider, contains('setAvatarFrame'));
    expect(themeProvider, contains('activeAvatarFrameId'));
    expect(themeProvider, contains('unlockedAvatarFrameIds'));
    expect(themeProvider, contains('CardSkinReward'));
    expect(themeProvider, contains('cardSkinRewards'));
    expect(themeProvider, contains('isCardSkinUnlocked'));
    expect(themeProvider, contains('unlockCardSkin'));
    expect(themeProvider, contains('setCardSkin'));
    expect(themeProvider, contains('activeCardSkinId'));
    expect(themeProvider, contains('unlockedCardSkinIds'));
    expect(
      themeScreen,
      contains("import '../providers/achievement_provider.dart';"),
    );
    expect(themeScreen, contains('achievementProvider.spendCoins('));
    expect(themeScreen, contains('时光币'));
    expect(themeScreen, contains('Icons.lock_outline'));
    expect(themeScreen, contains('专注背景'));
    expect(themeScreen, contains('兑换专注背景'));
    expect(themeScreen, contains('_focusBackdropPreview'));
    expect(themeScreen, contains('头像框'));
    expect(themeScreen, contains('兑换头像框'));
    expect(themeScreen, contains('_avatarFramePreview'));
    expect(themeScreen, contains('卡片皮肤'));
    expect(themeScreen, contains('兑换卡片皮肤'));
    expect(themeScreen, contains('_cardSkinPreview'));
    expect(achievementProvider, contains('Future<bool> spendCoins'));
    expect(backup, contains("'theme_shop_state'"));
    expect(cloudSync, contains("'theme_shop_state': 'theme_shop_state'"));
  });

  test('番茄钟页面展示已启用的专注背景装饰', () {
    final pomodoroScreen = File(
      'lib/screens/pomodoro_screen.dart',
    ).readAsStringSync();

    expect(pomodoroScreen, contains('activeFocusBackdrop'));
    expect(pomodoroScreen, contains('defaultFocusBackdropId'));
    expect(pomodoroScreen, contains('focusBackdrop.colors'));
    expect(pomodoroScreen, contains('focusBackdrop.name'));
  });

  test('我的页面展示已启用的头像框装饰', () {
    final mineScreen = File('lib/screens/mine_screen.dart').readAsStringSync();

    expect(mineScreen, contains('activeAvatarFrame'));
    expect(mineScreen, contains('defaultAvatarFrameId'));
    expect(mineScreen, contains('avatarFrame.colors'));
  });

  test('全局信息卡片应用已启用的卡片皮肤', () {
    final surface = File(
      'lib/widgets/surface_components.dart',
    ).readAsStringSync();

    expect(surface, contains('activeCardSkin'));
    expect(surface, contains('defaultCardSkinId'));
    expect(surface, contains('skinGradient'));
    expect(surface, contains('cardSkin.colors'));
  });
}
