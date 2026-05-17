class NotificationPermissionDeniedException implements Exception {
  final String message;

  const NotificationPermissionDeniedException([
    this.message = '系统通知未授权，提醒不会显示',
  ]);

  @override
  String toString() => 'NotificationPermissionDeniedException: $message';
}
