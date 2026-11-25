import 'package:duoyi/core/ai_schedule_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/notification_service.dart';
import 'package:duoyi/services/reminder_sync_issue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => I18n.setLocale(AppLocale.zh));
  for (final requested in AppLocale.values) {
    test('untyped reminder fallback honors explicit $requested locale', () {
      I18n.setLocale(requested == AppLocale.en ? AppLocale.zh : AppLocale.en);
      final expected = requested == AppLocale.en
          ? 'Reminder was not registered'
          : '提醒未注册';
      final legacy = NotificationScheduleIssue(
        title: 'Private diagnostic',
        message: 'Private diagnostic',
        happenedAt: DateTime(2026),
      );
      for (final issue in [
        null,
        StateError('Private diagnostic'),
        legacy,
        ReminderSyncIssue.literal('Private diagnostic'),
      ]) {
        expect(
          AiScheduleUiCopy.renderReminderIssue(issue, requested),
          expected,
        );
      }
    });
  }
}
