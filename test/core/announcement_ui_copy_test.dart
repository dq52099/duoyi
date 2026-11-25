import 'package:duoyi/core/announcement_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => I18n.setLocale(AppLocale.zh));

  for (final locale in AppLocale.values) {
    test('announcement states are localized in ${locale.name}', () {
      I18n.setLocale(locale);
      final labels = [
        AnnouncementUiCopy.loading,
        AnnouncementUiCopy.updating,
        AnnouncementUiCopy.accountChanging,
        AnnouncementUiCopy.loadFailed,
        AnnouncementUiCopy.refreshFailed,
        AnnouncementUiCopy.retry,
        AnnouncementUiCopy.refresh,
      ];
      expect(labels.every((label) => label.isNotEmpty), isTrue);
      if (locale == AppLocale.en) {
        expect(labels.any(RegExp(r'[\u3400-\u9fff]').hasMatch), isFalse);
      }
      final error = StateError('private-url?token=secret');
      expect(
        AnnouncementUiCopy.errorMessage(error),
        AnnouncementUiCopy.loadFailed,
      );
      expect(
        AnnouncementUiCopy.errorMessage(error, hasItems: true),
        AnnouncementUiCopy.refreshFailed,
      );
      expect(AnnouncementUiCopy.errorMessage(error), isNot(contains('secret')));
    });
  }

  test('retained typed network errors resolve using the current locale', () {
    const error = ApiException('连接服务器超时: private-url');
    I18n.setLocale(AppLocale.zh);
    expect(AnnouncementUiCopy.errorMessage(error), '连接超时，请稍后重试');
    I18n.setLocale(AppLocale.en);
    expect(
      AnnouncementUiCopy.errorMessage(error),
      'Connection timed out. Please try again.',
    );
    expect(
      AnnouncementUiCopy.errorMessage(error, hasItems: true),
      contains(AnnouncementUiCopy.refreshFailed),
    );
    expect(
      AnnouncementUiCopy.errorMessage(error),
      isNot(contains('private-url')),
    );
  });

  test('server diagnostics use the safe localized fallback', () {
    I18n.setLocale(AppLocale.en);
    for (final error in [
      const ApiException('503: private implementation details'),
      const ApiException('<html>upstream URL and diagnostics</html>'),
      FormatException('bad payload at private-url'),
    ]) {
      expect(
        AnnouncementUiCopy.errorMessage(error),
        AnnouncementUiCopy.loadFailed,
      );
    }
  });
}
