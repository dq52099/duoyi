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

  const NotificationScheduleUnavailableException({
    required this.title,
    required this.message,
    this.scheduledTime,
    this.relatedId,
  });

  @override
  String toString() => '$title：$message';
}
