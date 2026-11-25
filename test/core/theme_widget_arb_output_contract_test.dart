// NEW832: exact API output contract frozen from released audit817.
// Expected values are literals, never read from the ARBs/generated output.
import 'package:duoyi/core/data_settings_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:flutter_test/flutter_test.dart';

// Leading/trailing whitespace, decomposed accent, emoji, braces, dollar,
// quotes and control characters must pass through without normalization.
const _unicodeInput = '  自定义🧩 é/É • {name} \$count \'引号\'\n下一行\t  ';

void main() {
  late AppLocale originalLocale;
  setUp(() {
    originalLocale = I18n.current;
  });
  tearDown(() => I18n.setLocale(originalLocale));

  test('theme widget getters preserve frozen817 outputs across zh en zh', () {
    final contracts = <_OutputContract>[
      _OutputContract(
        'themeSaveFailed',
        () => DataSettingsUiCopy.themeSaveFailed,
        '主题保存失败',
        'Failed to save theme settings',
      ),
      _OutputContract(
        'rewardShopReason',
        () => DataSettingsUiCopy.rewardShopReason,
        '奖励商店主题装饰',
        'Reward shop theme decoration',
      ),
      _OutputContract(
        'unlockThemeFirst',
        () => DataSettingsUiCopy.unlockThemeFirst,
        '请先解锁该主题',
        'Please unlock this theme first',
      ),
      _OutputContract(
        'unlockCardSkinFirst',
        () => DataSettingsUiCopy.unlockCardSkinFirst,
        '请先解锁该卡片皮肤',
        'Please unlock this card skin first',
      ),
      _OutputContract(
        'widgetFollowCurrentTheme',
        () => DataSettingsUiCopy.widgetFollowCurrentTheme,
        '跟随当前主题',
        'Follow Current Theme',
      ),
      _OutputContract(
        'widgetFollowCardSkin',
        () => DataSettingsUiCopy.widgetFollowCardSkin,
        '跟随卡片皮肤',
        'Follow Card Skin',
      ),
      _OutputContract(
        'widgetThemeTitle',
        () => DataSettingsUiCopy.widgetThemeTitle,
        '桌面小组件主题',
        'Desktop Widget Theme',
      ),
      _OutputContract(
        'widgetThemeSubtitle',
        () => DataSettingsUiCopy.widgetThemeSubtitle,
        '单独调整桌面小组件背景和卡片皮肤',
        'Adjust desktop widget background and card skin individually',
      ),
      _OutputContract(
        'widgetBackgroundLabel',
        () => DataSettingsUiCopy.widgetBackgroundLabel,
        '背景图',
        'Background',
      ),
      _OutputContract(
        'widgetCardSkinLabel',
        () => DataSettingsUiCopy.widgetCardSkinLabel,
        '卡片皮肤',
        'Card Skin',
      ),
      _OutputContract(
        'focusBackdropSectionTitle',
        () => DataSettingsUiCopy.focusBackdropSectionTitle,
        '专注背景',
        'Focus Backdrops',
      ),
      _OutputContract(
        'focusBackdropSectionSubtitle',
        () => DataSettingsUiCopy.focusBackdropSectionSubtitle,
        '用时光币兑换番茄钟卡片装饰',
        'Redeem Pomodoro card decorations with Time Coins',
      ),
      _OutputContract(
        'avatarFrameSectionTitle',
        () => DataSettingsUiCopy.avatarFrameSectionTitle,
        '头像框',
        'Avatar Frames',
      ),
      _OutputContract(
        'avatarFrameSectionSubtitle',
        () => DataSettingsUiCopy.avatarFrameSectionSubtitle,
        '用时光币兑换我的页头像装饰',
        'Redeem Profile avatar decorations with Time Coins',
      ),
      _OutputContract(
        'cardSkinSectionTitle',
        () => DataSettingsUiCopy.cardSkinSectionTitle,
        '卡片皮肤',
        'Card Skins',
      ),
      _OutputContract(
        'cardSkinSectionSubtitle',
        () => DataSettingsUiCopy.cardSkinSectionSubtitle,
        '用时光币兑换信息卡片质感',
        'Redeem information card styles with Time Coins',
      ),
      _OutputContract(
        'widgetSyncNoticeTitle',
        () => DataSettingsUiCopy.widgetSyncNoticeTitle,
        '小组件主题',
        'Widget Theme',
      ),
      _OutputContract(
        'widgetSyncNoticeSubtitle',
        () => DataSettingsUiCopy.widgetSyncNoticeSubtitle,
        '背景图和卡片皮肤会同步到手机桌面小组件',
        'Background and card skin sync to device home widgets',
      ),
    ];
    _expectLocaleCycle(contracts);
  });

  test('theme widget interpolation preserves empty and Unicode inputs across zh en zh', () {
    final contracts = <_OutputContract>[
      _OutputContract(
        'redeemThemeTitle input 0',
        () => DataSettingsUiCopy.redeemThemeTitle(''),
        '兑换主题：',
        'Redeem theme: ',
      ),
      _OutputContract(
        'redeemThemeTitle input 1',
        () => DataSettingsUiCopy.redeemThemeTitle('Theme 01'),
        '兑换主题：Theme 01',
        'Redeem theme: Theme 01',
      ),
      _OutputContract(
        'redeemThemeTitle input 2',
        () => DataSettingsUiCopy.redeemThemeTitle(_unicodeInput),
        '兑换主题：  自定义🧩 é/É • {name} \$count \'引号\'\n下一行\t  ',
        'Redeem theme:   自定义🧩 é/É • {name} \$count \'引号\'\n下一行\t  ',
      ),
      _OutputContract(
        'redeemFocusBackdropTitle input 0',
        () => DataSettingsUiCopy.redeemFocusBackdropTitle(''),
        '兑换专注背景：',
        'Redeem focus backdrop: ',
      ),
      _OutputContract(
        'redeemFocusBackdropTitle input 1',
        () => DataSettingsUiCopy.redeemFocusBackdropTitle('Theme 01'),
        '兑换专注背景：Theme 01',
        'Redeem focus backdrop: Theme 01',
      ),
      _OutputContract(
        'redeemFocusBackdropTitle input 2',
        () => DataSettingsUiCopy.redeemFocusBackdropTitle(_unicodeInput),
        '兑换专注背景：  自定义🧩 é/É • {name} \$count \'引号\'\n下一行\t  ',
        'Redeem focus backdrop:   自定义🧩 é/É • {name} \$count \'引号\'\n下一行\t  ',
      ),
      _OutputContract(
        'redeemAvatarFrameTitle input 0',
        () => DataSettingsUiCopy.redeemAvatarFrameTitle(''),
        '兑换头像框：',
        'Redeem avatar frame: ',
      ),
      _OutputContract(
        'redeemAvatarFrameTitle input 1',
        () => DataSettingsUiCopy.redeemAvatarFrameTitle('Theme 01'),
        '兑换头像框：Theme 01',
        'Redeem avatar frame: Theme 01',
      ),
      _OutputContract(
        'redeemAvatarFrameTitle input 2',
        () => DataSettingsUiCopy.redeemAvatarFrameTitle(_unicodeInput),
        '兑换头像框：  自定义🧩 é/É • {name} \$count \'引号\'\n下一行\t  ',
        'Redeem avatar frame:   自定义🧩 é/É • {name} \$count \'引号\'\n下一行\t  ',
      ),
      _OutputContract(
        'redeemCardSkinTitle input 0',
        () => DataSettingsUiCopy.redeemCardSkinTitle(''),
        '兑换卡片皮肤：',
        'Redeem card skin: ',
      ),
      _OutputContract(
        'redeemCardSkinTitle input 1',
        () => DataSettingsUiCopy.redeemCardSkinTitle('Theme 01'),
        '兑换卡片皮肤：Theme 01',
        'Redeem card skin: Theme 01',
      ),
      _OutputContract(
        'redeemCardSkinTitle input 2',
        () => DataSettingsUiCopy.redeemCardSkinTitle(_unicodeInput),
        '兑换卡片皮肤：  自定义🧩 é/É • {name} \$count \'引号\'\n下一行\t  ',
        'Redeem card skin:   自定义🧩 é/É • {name} \$count \'引号\'\n下一行\t  ',
      ),
      _OutputContract(
        'themeApplied input 0',
        () => DataSettingsUiCopy.themeApplied(''),
        '已启用 ',
        'Applied ',
      ),
      _OutputContract(
        'themeApplied input 1',
        () => DataSettingsUiCopy.themeApplied('Theme 01'),
        '已启用 Theme 01',
        'Applied Theme 01',
      ),
      _OutputContract(
        'themeApplied input 2',
        () => DataSettingsUiCopy.themeApplied(_unicodeInput),
        '已启用   自定义🧩 é/É • {name} \$count \'引号\'\n下一行\t  ',
        'Applied   自定义🧩 é/É • {name} \$count \'引号\'\n下一行\t  ',
      ),
      _OutputContract(
        'themeRedeemedAndApplied input 0',
        () => DataSettingsUiCopy.themeRedeemedAndApplied(''),
        '已兑换并启用 ',
        'Redeemed and applied ',
      ),
      _OutputContract(
        'themeRedeemedAndApplied input 1',
        () => DataSettingsUiCopy.themeRedeemedAndApplied('Theme 01'),
        '已兑换并启用 Theme 01',
        'Redeemed and applied Theme 01',
      ),
      _OutputContract(
        'themeRedeemedAndApplied input 2',
        () => DataSettingsUiCopy.themeRedeemedAndApplied(_unicodeInput),
        '已兑换并启用   自定义🧩 é/É • {name} \$count \'引号\'\n下一行\t  ',
        'Redeemed and applied   自定义🧩 é/É • {name} \$count \'引号\'\n下一行\t  ',
      ),
      _OutputContract(
        'widgetBackgroundSwitched input 0',
        () => DataSettingsUiCopy.widgetBackgroundSwitched(''),
        '小组件背景已切换为 ',
        'Widget background switched to ',
      ),
      _OutputContract(
        'widgetBackgroundSwitched input 1',
        () => DataSettingsUiCopy.widgetBackgroundSwitched('Theme 01'),
        '小组件背景已切换为 Theme 01',
        'Widget background switched to Theme 01',
      ),
      _OutputContract(
        'widgetBackgroundSwitched input 2',
        () => DataSettingsUiCopy.widgetBackgroundSwitched(_unicodeInput),
        '小组件背景已切换为   自定义🧩 é/É • {name} \$count \'引号\'\n下一行\t  ',
        'Widget background switched to   自定义🧩 é/É • {name} \$count \'引号\'\n下一行\t  ',
      ),
      _OutputContract(
        'widgetCardSkinSwitched input 0',
        () => DataSettingsUiCopy.widgetCardSkinSwitched(''),
        '小组件卡片皮肤已切换为 ',
        'Widget card skin switched to ',
      ),
      _OutputContract(
        'widgetCardSkinSwitched input 1',
        () => DataSettingsUiCopy.widgetCardSkinSwitched('Theme 01'),
        '小组件卡片皮肤已切换为 Theme 01',
        'Widget card skin switched to Theme 01',
      ),
      _OutputContract(
        'widgetCardSkinSwitched input 2',
        () => DataSettingsUiCopy.widgetCardSkinSwitched(_unicodeInput),
        '小组件卡片皮肤已切换为   自定义🧩 é/É • {name} \$count \'引号\'\n下一行\t  ',
        'Widget card skin switched to   自定义🧩 é/É • {name} \$count \'引号\'\n下一行\t  ',
      ),
    ];
    _expectLocaleCycle(contracts);
  });

  test('theme widget integer outputs preserve zero one negative and large values across zh en zh', () {
    final contracts = <_OutputContract>[
      _OutputContract(
        'insufficientCoins -2147483648',
        () => DataSettingsUiCopy.insufficientCoins(-2147483648),
        '时光币不足，还差 -2147483648',
        'Not enough Time Coins, need -2147483648 more',
      ),
      _OutputContract(
        'insufficientCoins -1',
        () => DataSettingsUiCopy.insufficientCoins(-1),
        '时光币不足，还差 -1',
        'Not enough Time Coins, need -1 more',
      ),
      _OutputContract(
        'insufficientCoins 0',
        () => DataSettingsUiCopy.insufficientCoins(0),
        '时光币不足，还差 0',
        'Not enough Time Coins, need 0 more',
      ),
      _OutputContract(
        'insufficientCoins 1',
        () => DataSettingsUiCopy.insufficientCoins(1),
        '时光币不足，还差 1',
        'Not enough Time Coins, need 1 more',
      ),
      _OutputContract(
        'insufficientCoins 42',
        () => DataSettingsUiCopy.insufficientCoins(42),
        '时光币不足，还差 42',
        'Not enough Time Coins, need 42 more',
      ),
      _OutputContract(
        'insufficientCoins 2147483647',
        () => DataSettingsUiCopy.insufficientCoins(2147483647),
        '时光币不足，还差 2147483647',
        'Not enough Time Coins, need 2147483647 more',
      ),
      _OutputContract(
        'coinCount -2147483648',
        () => DataSettingsUiCopy.coinCount(-2147483648),
        '时光币 -2147483648',
        'Time Coins -2147483648',
      ),
      _OutputContract(
        'coinCount -1',
        () => DataSettingsUiCopy.coinCount(-1),
        '时光币 -1',
        'Time Coins -1',
      ),
      _OutputContract(
        'coinCount 0',
        () => DataSettingsUiCopy.coinCount(0),
        '时光币 0',
        'Time Coins 0',
      ),
      _OutputContract(
        'coinCount 1',
        () => DataSettingsUiCopy.coinCount(1),
        '时光币 1',
        'Time Coins 1',
      ),
      _OutputContract(
        'coinCount 42',
        () => DataSettingsUiCopy.coinCount(42),
        '时光币 42',
        'Time Coins 42',
      ),
      _OutputContract(
        'coinCount 2147483647',
        () => DataSettingsUiCopy.coinCount(2147483647),
        '时光币 2147483647',
        'Time Coins 2147483647',
      ),
      _OutputContract(
        'coinCost -2147483648',
        () => DataSettingsUiCopy.coinCost(-2147483648),
        '-2147483648 币',
        '-2147483648 Coins',
      ),
      _OutputContract(
        'coinCost -1',
        () => DataSettingsUiCopy.coinCost(-1),
        '-1 币',
        '-1 Coins',
      ),
      _OutputContract(
        'coinCost 0',
        () => DataSettingsUiCopy.coinCost(0),
        '0 币',
        '0 Coins',
      ),
      _OutputContract(
        'coinCost 1',
        () => DataSettingsUiCopy.coinCost(1),
        '1 币',
        '1 Coins',
      ),
      _OutputContract(
        'coinCost 42',
        () => DataSettingsUiCopy.coinCost(42),
        '42 币',
        '42 Coins',
      ),
      _OutputContract(
        'coinCost 2147483647',
        () => DataSettingsUiCopy.coinCost(2147483647),
        '2147483647 币',
        '2147483647 Coins',
      ),
    ];
    _expectLocaleCycle(contracts);
  });

  test('theme widget builtins preserve all frozen817 outputs from real provider definitions across zh en zh', () {
    final contracts = <_OutputContract>[];
    for (final family in _rewardFamilies()) {
      expect(
        family.rewards.map((reward) => reward.id),
        unorderedEquals(family.expected.keys),
        reason: family.label,
      );
      for (final reward in family.rewards) {
        final expected = family.expected[reward.id]!;
        expect(reward.name, expected.zhName, reason: reward.id);
        expect(reward.description, expected.zhDescription, reason: reward.id);
        contracts.addAll([
          _OutputContract(
            '${family.label} ${reward.id} name',
            () => family.readName(reward.id, reward.name),
            expected.zhName,
            expected.enName,
          ),
          _OutputContract(
            '${family.label} ${reward.id} description',
            () => family.readDescription(reward.id, reward.description),
            expected.zhDescription,
            expected.enDescription,
          ),
        ]);
      }
    }
    _expectLocaleCycle(contracts);
  });

  test('theme widget known IDs preserve custom Chinese fallback and mapped English across zh en zh', () {
    final contracts = <_OutputContract>[];
    for (final family in _rewardFamilies()) {
      for (final reward in family.rewards) {
        final expected = family.expected[reward.id]!;
        for (final fallback in ['', _unicodeInput, '用户专用背景 / User-owned']) {
          contracts.addAll([
            _OutputContract(
              '${family.label} ${reward.id} custom name $fallback',
              () => family.readName(reward.id, fallback),
              fallback,
              expected.enName,
            ),
            _OutputContract(
              '${family.label} ${reward.id} custom description $fallback',
              () => family.readDescription(reward.id, fallback),
              fallback,
              expected.enDescription,
            ),
          ]);
        }
      }
    }
    _expectLocaleCycle(contracts);
  });

  test('theme widget unknown and cross family IDs pass fallback through across zh en zh', () {
    final contracts = <_OutputContract>[];
    final families = _rewardFamilies();
    final allBuiltinIds = {
      for (final family in families) ...family.expected.keys,
    };
    for (final family in families) {
      final unknownIds = <String>[
        '',
        'custom-reward-832',
        'CLASSIC_FOCUS',
        'classic_focus ',
        'follow_theme',
        'follow_card_skin',
        ...allBuiltinIds.where((id) => !family.expected.containsKey(id)),
      ];
      for (final id in unknownIds) {
        for (final fallback in ['', _unicodeInput, '未登记 / Unregistered']) {
          contracts.addAll([
            _OutputContract(
              '${family.label} unknown $id name $fallback',
              () => family.readName(id, fallback),
              fallback,
              fallback,
            ),
            _OutputContract(
              '${family.label} unknown $id description $fallback',
              () => family.readDescription(id, fallback),
              fallback,
              fallback,
            ),
          ]);
        }
      }
    }
    _expectLocaleCycle(contracts);
  });
}

// Keep the same closures alive for the complete round trip. Only call the
// public API after selecting each locale; cached localized output will fail.
void _expectLocaleCycle(List<_OutputContract> contracts) {
  for (final locale in [AppLocale.zh, AppLocale.en, AppLocale.zh]) {
    I18n.setLocale(locale);
    expect(I18n.current, locale);
    for (final contract in contracts) {
      expect(
        contract.read(),
        locale == AppLocale.zh ? contract.zh : contract.en,
        reason: '${contract.label} in $locale',
      );
    }
  }
}

class _OutputContract {
  const _OutputContract(this.label, this.read, this.zh, this.en);
  final String label;
  final String Function() read;
  final String zh;
  final String en;
}

typedef _RewardInput = ({String id, String name, String description});
typedef _RewardOutput = ({
  String zhName,
  String zhDescription,
  String enName,
  String enDescription,
});

class _RewardFamily {
  const _RewardFamily({
    required this.label,
    required this.rewards,
    required this.readName,
    required this.readDescription,
    required this.expected,
  });
  final String label;
  final List<_RewardInput> rewards;
  final String Function(String, String) readName;
  final String Function(String, String) readDescription;
  final Map<String, _RewardOutput> expected;
}

// These adapters consume real static Provider definitions, without creating
// a Provider, loading preferences, unlocking rewards or writing records.
List<_RewardFamily> _rewardFamilies() => [
  _RewardFamily(
    label: 'focusBackdrop',
    rewards: [
      for (final reward in ThemeProvider.focusBackdropRewards)
        (id: reward.id, name: reward.name, description: reward.description),
    ],
    readName: DataSettingsUiCopy.focusBackdropName,
    readDescription: DataSettingsUiCopy.focusBackdropDescription,
    expected: const {
      'classic_focus': (
        zhName: '经典专注',
        zhDescription: '简洁的番茄钟渐变背景',
        enName: 'Classic Focus',
        enDescription: 'Clean gradient Pomodoro background',
      ),
      'morning_focus': (
        zhName: '晨光书桌',
        zhDescription: '适合清晨阅读和学习的暖色背景',
        enName: 'Morning Desk',
        enDescription: 'Warm background ideal for morning study and reading',
      ),
      'forest_focus': (
        zhName: '林间深呼吸',
        zhDescription: '适合长时间深度工作的自然绿色背景',
        enName: 'Forest Breeze',
        enDescription: 'Natural green background for deep, sustained focus',
      ),
      'ocean_focus': (
        zhName: '海岸静流',
        zhDescription: '适合复盘、写作和低压专注的蓝绿色背景',
        enName: 'Ocean Flow',
        enDescription: 'Calm cyan background for review and low-pressure focus',
      ),
      'night_focus': (
        zhName: '夜航模式',
        zhDescription: '适合夜间学习的低亮度深色背景',
        enName: 'Night Flight',
        enDescription: 'Low-brightness dark background for night study',
      ),
    },
  ),
  _RewardFamily(
    label: 'avatarFrame',
    rewards: [
      for (final reward in ThemeProvider.avatarFrameRewards)
        (id: reward.id, name: reward.name, description: reward.description),
    ],
    readName: DataSettingsUiCopy.avatarFrameName,
    readDescription: DataSettingsUiCopy.avatarFrameDescription,
    expected: const {
      'simple_frame': (
        zhName: '简洁头像',
        zhDescription: '默认头像样式',
        enName: 'Simple Frame',
        enDescription: 'Default avatar frame style',
      ),
      'golden_frame': (
        zhName: '金色勋章框',
        zhDescription: '适合成就达人展示的金色头像框',
        enName: 'Golden Medal Frame',
        enDescription: 'Golden frame for achievement masters',
      ),
      'forest_frame': (
        zhName: '绿叶守护框',
        zhDescription: '适合习惯连续打卡的自然头像框',
        enName: 'Green Leaf Frame',
        enDescription: 'Natural leafy frame for consistent habit streaks',
      ),
      'aurora_frame': (
        zhName: '极光能量框',
        zhDescription: '适合高效专注周的流光头像框',
        enName: 'Aurora Energy Frame',
        enDescription: 'Glowing aurora frame for productive weeks',
      ),
    },
  ),
  _RewardFamily(
    label: 'cardSkin',
    rewards: [
      for (final reward in ThemeProvider.cardSkinRewards)
        (id: reward.id, name: reward.name, description: reward.description),
    ],
    readName: DataSettingsUiCopy.cardSkinName,
    readDescription: DataSettingsUiCopy.cardSkinDescription,
    expected: const {
      'plain_card': (
        zhName: '素净卡片',
        zhDescription: '默认信息卡片样式',
        enName: 'Plain Card',
        enDescription: 'Default card surface style',
      ),
      'paper_card': (
        zhName: '纸感计划卡',
        zhDescription: '适合日程和待办整理的柔和纸感',
        enName: 'Paper Planner Card',
        enDescription: 'Gentle paper texture for schedules and todos',
      ),
      'mint_card': (
        zhName: '薄荷清单卡',
        zhDescription: '适合习惯和专注记录的清爽卡片',
        enName: 'Mint Checklist Card',
        enDescription: 'Refreshing card style for habits and focus logs',
      ),
      'starlight_card': (
        zhName: '星光玻璃卡',
        zhDescription: '适合夜间复盘的低亮度玻璃质感',
        enName: 'Starlight Glass Card',
        enDescription: 'Low-light glass texture for evening reviews',
      ),
    },
  ),
];
