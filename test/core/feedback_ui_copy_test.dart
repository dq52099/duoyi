import 'package:duoyi/core/feedback_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:test/test.dart';

void main() {
  tearDown(() => I18n.setLocale(AppLocale.zh));
  for (final locale in AppLocale.values) {
    test('feedback labels render explicit locale independently: $locale', () {
      I18n.setLocale(locale == AppLocale.zh ? AppLocale.en : AppLocale.zh);
      final expected = locale == AppLocale.en ? 'Bug report' : '问题反馈';
      expect(FeedbackUiCopy.categoryLabel('bug', locale), expected);
      expect(
        FeedbackUiCopy.statusLabel('in_progress', locale),
        locale == AppLocale.en ? 'In progress' : '处理中',
      );
      expect(
        FeedbackUiCopy.paginationPage(2, 5, locale),
        locale == AppLocale.en ? 'Page 2/5' : '第 2/5 页',
      );
    });

    for (final diagnostic in [
      '404: Not Found /api/internal?token=synthetic-secret',
      '400: SQL constraint failed in accounts table',
    ]) {
      test(
        'feedback errors hide diagnostic response in $locale: $diagnostic',
        () {
          final result = FeedbackUiCopy.formatError(
            ApiException(diagnostic),
            locale: locale,
          );
          expect(result, isNot(contains('synthetic-secret')));
          expect(result, isNot(contains('/api/internal')));
          expect(result, isNot(contains('SQL')));
          expect(result, isNot(contains('accounts table')));
          expect(result, isNot(contains('Not Found')));
          expect(result, isNotEmpty);
          if (locale == AppLocale.en) {
            expect(RegExp(r'[\u3400-\u9fff]').hasMatch(result), isFalse);
          }
        },
      );
    }
  }
}
