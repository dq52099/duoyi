import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/share_ui_copy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => I18n.setLocale(AppLocale.zh));
  tearDown(() => I18n.setLocale(AppLocale.zh));

  test('English member counts use singular only for one member', () {
    expect(
      ShareUiCopy.membersCount(0, 'Owner', AppLocale.en),
      '0 members · Owner',
    );
    expect(
      ShareUiCopy.membersCount(1, 'Owner', AppLocale.en),
      '1 member · Owner',
    );
    expect(
      ShareUiCopy.membersCount(2, 'Owner', AppLocale.en),
      '2 members · Owner',
    );
  });

  test('Chinese member counts preserve the supplied role label', () {
    expect(ShareUiCopy.membersCount(1, '拥有者', AppLocale.zh), '1 位成员 · 拥有者');
    expect(
      ShareUiCopy.membersCount(2, '自定义 / Custom', AppLocale.zh),
      '2 位成员 · 自定义 / Custom',
    );
  });

  test('Explicit copy locale leaves the global selection unchanged', () {
    expect(
      ShareUiCopy.membersCount(1, 'literal role', AppLocale.en),
      '1 member · literal role',
    );
    expect(I18n.current, AppLocale.zh);
  });

  test('Implicit copy locale follows the current language', () {
    expect(ShareUiCopy.membersCount(1, 'Owner'), '1 位成员 · Owner');
    I18n.setLocale(AppLocale.en);
    expect(ShareUiCopy.membersCount(1, 'Owner'), '1 member · Owner');
  });
}
