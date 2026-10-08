import 'package:duoyi/core/data_settings_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => I18n.setLocale(AppLocale.zh));

  test('every built-in reward has English display copy for its real ID', () {
    I18n.setLocale(AppLocale.en);
    final labels = <String>[
      for (final reward in ThemeProvider.focusBackdropRewards) ...[
        DataSettingsUiCopy.focusBackdropName(reward.id, reward.name),
        DataSettingsUiCopy.focusBackdropDescription(
          reward.id,
          reward.description,
        ),
      ],
      for (final reward in ThemeProvider.avatarFrameRewards) ...[
        DataSettingsUiCopy.avatarFrameName(reward.id, reward.name),
        DataSettingsUiCopy.avatarFrameDescription(reward.id, reward.description),
      ],
      for (final reward in ThemeProvider.cardSkinRewards) ...[
        DataSettingsUiCopy.cardSkinName(reward.id, reward.name),
        DataSettingsUiCopy.cardSkinDescription(reward.id, reward.description),
      ],
    ];
    expect(labels, everyElement(isNotEmpty));
    expect(labels.where(RegExp(r'[\u3400-\u9fff]').hasMatch), isEmpty);
  });

  test('custom reward text remains unchanged in either language', () {
    for (final locale in AppLocale.values) {
      I18n.setLocale(locale);
      expect(
        DataSettingsUiCopy.focusBackdropName('custom-id', '我的背景'),
        '我的背景',
      );
      expect(
        DataSettingsUiCopy.avatarFrameDescription('custom-id', 'My frame'),
        'My frame',
      );
    }
  });
}
