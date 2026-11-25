import 'package:duoyi/core/goal_icons.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => I18n.setLocale(AppLocale.zh));

  test('Every built-in goal icon has a specific English label', () {
    for (final choice in goalIconChoices) {
      final english = choice.localizedLabel(AppLocale.en);
      expect(english, isNotEmpty, reason: choice.name);
      expect(english, isNot('Goal'), reason: choice.name);
      expect(english, isNot(matches(RegExp(r'[\u3400-\u9fff]'))));
      expect(choice.localizedLabel(AppLocale.zh), choice.label);
    }
  });

  test('Explicit icon locale does not change the selected app language', () {
    I18n.setLocale(AppLocale.zh);
    expect(goalIconLabel('flag', AppLocale.en), 'Flag');
    expect(I18n.current, AppLocale.zh);
    I18n.setLocale(AppLocale.en);
    expect(goalIconLabel('flag'), 'Flag');
    expect(goalIconLabel('unknown'), 'Flag');
    expect(goalIconLabel('flag', AppLocale.zh), '旗帜');
    expect(I18n.current, AppLocale.en);
  });
}
