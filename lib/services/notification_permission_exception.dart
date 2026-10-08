import '../core/i18n.dart';
import 'reminder_issue_copy.dart';

class NotificationPermissionDeniedException implements Exception {
  final String message;

  const NotificationPermissionDeniedException([
    this.message = '系统通知未授权，提醒不会显示',
  ]);

  @override
  String toString() => 'NotificationPermissionDeniedException: $message';
}

class NotificationScheduleUnavailableException implements Exception {
  final String title;
  final String message;
  final DateTime? scheduledTime;
  final String? relatedId;
  final ReminderIssueCopy? copy;

  const NotificationScheduleUnavailableException({
    required this.title,
    required this.message,
    this.scheduledTime,
    this.relatedId,
    this.copy,
  });

  String renderTitle({AppLocale? locale}) =>
      copy?.renderTitle(fallback: title, locale: locale) ?? title;

  String renderMessage({AppLocale? locale}) =>
      copy?.renderMessage(fallback: message, locale: locale) ?? message;

  @override
  String toString() => '$title：$message';
}
