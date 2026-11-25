import 'package:duoyi/core/admin_feedback_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => I18n.setLocale(AppLocale.zh));

  test(
    'Feedback fixed labels follow locale while unknown data stays literal',
    () {
      const token = 'future 原文 category';
      for (final locale in AppLocale.values) {
        expect(AdminFeedbackUiCopy.categoryLabel(token, locale), token);
        expect(AdminFeedbackUiCopy.statusLabel(token, locale), token);
        expect(AdminFeedbackUiCopy.sortLabel(token, locale), token);
        expect(
          AdminFeedbackUiCopy.replyPreview(token, locale),
          contains(token),
        );
        expect(
          AdminFeedbackUiCopy.exported('/tmp/literal 原文.csv', locale),
          contains('/tmp/literal 原文.csv'),
        );
      }
      I18n.setLocale(AppLocale.en);
      expect(AdminFeedbackUiCopy.titleFor(), 'Feedback');
      expect(AdminFeedbackUiCopy.categoryLabel('bug'), 'Bug report');
      expect(AdminFeedbackUiCopy.statusLabel('in_progress'), 'In progress');
      expect(
        AdminFeedbackUiCopy.sortLabel('updated_desc'),
        'Recently updated first',
      );
      expect(AdminFeedbackUiCopy.titleFor(AppLocale.zh), '反馈列表');
      expect(AdminFeedbackUiCopy.categoryLabel('bug', AppLocale.zh), '问题反馈');
    },
  );

  test(
    'Feedback email verification accepts bools and SQLite zero/one only',
    () {
      for (final value in [true, 1]) {
        expect(AdminFeedbackUiCopy.isEmailVerified(value), isTrue);
      }
      for (final value in [false, 0, null, '1', 'true', 2]) {
        expect(AdminFeedbackUiCopy.isEmailVerified(value), isFalse);
      }
      expect(
        AdminFeedbackUiCopy.email('literal@example.test', true, AppLocale.en),
        'literal@example.test (verified)',
      );
      expect(
        AdminFeedbackUiCopy.email('literal@example.test', false, AppLocale.zh),
        'literal@example.test (未验证)',
      );
    },
  );

  test('Feedback bulk and export copy states the bounded scope', () {
    expect(AdminFeedbackUiCopy.bulkLimitFor(AppLocale.en), contains('100'));
    expect(AdminFeedbackUiCopy.bulkLimitFor(AppLocale.zh), contains('100'));
    expect(
      AdminFeedbackUiCopy.summaryHint(12000, 'created_desc', AppLocale.en),
      contains('first 5,000'),
    );
    expect(
      AdminFeedbackUiCopy.summaryHint(12000, 'created_desc', AppLocale.zh),
      contains('前 5000 条'),
    );
    expect(
      AdminFeedbackUiCopy.bulkMessage(100, 'resolved', AppLocale.en),
      contains('100'),
    );
    expect(
      AdminFeedbackUiCopy.bulkSaved(100, 'resolved', AppLocale.en),
      '100 items marked as Resolved',
    );
    expect(
      AdminFeedbackUiCopy.refreshFailed('Reply saved', AppLocale.en),
      'Reply saved. The list could not refresh. Refresh to see the result.',
    );
  });
}
