import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/notification_history_policy.dart';
import 'package:duoyi/core/notification_ui_copy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => I18n.setLocale(AppLocale.zh));
  tearDown(() => I18n.setLocale(AppLocale.zh));

  test('Retention title follows Chinese English and Chinese selections', () {
    expect(NotificationUiCopy.historyRetentionTitle, '通知记录保留');
    I18n.setLocale(AppLocale.en);
    expect(
      NotificationUiCopy.historyRetentionTitle,
      'Notification History Retention',
    );
    I18n.setLocale(AppLocale.zh);
    expect(NotificationUiCopy.historyRetentionTitle, '通知记录保留');
  });

  test('Chinese retention options preserve every supported limit', () {
    for (final limit in NotificationHistoryPolicy.options) {
      expect(NotificationUiCopy.historyRetentionItem(limit), '$limit 条');
      expect(
        NotificationUiCopy.historyRetentionSubtitle(limit),
        '最多保留 $limit 条历史，调低后会裁剪旧记录',
      );
    }
    expect(I18n.current, AppLocale.zh);
  });

  test('English retention options preserve limits and explain trimming', () {
    I18n.setLocale(AppLocale.en);
    for (final limit in NotificationHistoryPolicy.options) {
      expect(NotificationUiCopy.historyRetentionItem(limit), '$limit items');
      expect(
        NotificationUiCopy.historyRetentionSubtitle(limit),
        'Retain up to $limit notifications. Lower values trim older logs.',
      );
      expect(
        NotificationUiCopy.historyRetentionSubtitle(limit),
        isNot(matches(RegExp(r'[\u3400-\u9fff]'))),
      );
    }
    expect(I18n.current, AppLocale.en);
  });
}
