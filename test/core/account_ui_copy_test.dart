import 'package:duoyi/core/account_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => I18n.setLocale(AppLocale.zh));

  for (final scenario in [
    (
      details: [
        '账号已发生变化，请在当前账号重试操作。',
        'Account has changed. Try again in the current account.',
      ],
      chinese: '账号已切换，请重新打开页面后再操作',
      english: 'Account changed. Reopen this page before trying again.',
    ),
    (
      details: ['账号正在切换，请稍后重试。', 'Account is switching. Please retry.'],
      chinese: '账号正在切换，请稍候再试',
      english: 'Account is switching. Please wait and try again.',
    ),
  ]) {
    test('account boundary feedback follows locale: ${scenario.english}', () {
      for (final detail in scenario.details) {
        for (final error in <Object>[detail, ApiException(detail)]) {
          I18n.setLocale(AppLocale.zh);
          expect(AccountUiCopy.formatError(error), scenario.chinese);
          I18n.setLocale(AppLocale.en);
          expect(AccountUiCopy.formatError(error), scenario.english);
          I18n.setLocale(AppLocale.zh);
          expect(AccountUiCopy.formatError(error), scenario.chinese);
        }
      }
    });
  }

  test(
    'verification rate limits advise waiting rather than replacing the code',
    () {
      I18n.setLocale(AppLocale.zh);
      final message = AccountUiCopy.formatError(
        const ApiException('429: 验证码错误次数过多，请稍后再试'),
      );
      expect(message, contains('稍后'));
      expect(message, isNot(contains('重新获取')));
      expect(message, isNot(contains('429')));
      I18n.setLocale(AppLocale.en);
      final english = AccountUiCopy.formatError(
        const ApiException('429: 验证码错误次数过多，请稍后再试'),
      );
      expect(english.toLowerCase(), anyOf(contains('later'), contains('wait')));
      expect(english, isNot(matches(RegExp(r'[\u4e00-\u9fff]'))));
    },
  );

  for (final detail in [
    'Invalid or expired token',
    'Account disabled',
    'Registration disabled',
    'Invalid invite code',
    '用户名或邮箱已被使用',
    '当前密码不正确',
  ]) {
    test('backend account detail is localized: $detail', () {
      I18n.setLocale(AppLocale.zh);
      final chinese = AccountUiCopy.formatError(ApiException(detail));
      expect(chinese, matches(RegExp(r'[\u4e00-\u9fff]')));
      I18n.setLocale(AppLocale.en);
      final english = AccountUiCopy.formatError(ApiException(detail));
      expect(english, isNotEmpty);
      expect(english, isNot(matches(RegExp(r'[\u4e00-\u9fff]'))));
    });
  }

  test(
    'unknown exceptions and upstream pages cannot expose technical details',
    () {
      for (final locale in AppLocale.values) {
        I18n.setLocale(locale);
        for (final error in [
          StateError('https://example.test/?token=private'),
          const ApiException('502: <html>private proxy error</html>'),
          const ApiException('接口返回结构错误：private payload'),
        ]) {
          final message = AccountUiCopy.formatError(error);
          expect(message, isNotEmpty);
          expect(message, isNot(contains('private')));
          expect(message, isNot(contains('<html>')));
          expect(message, isNot(contains('StateError')));
        }
      }
    },
  );
}
