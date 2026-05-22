import 'package:flutter/foundation.dart';

@immutable
class NotificationHistoryPolicy {
  static const preferenceKey = 'pref_notification_history_limit';
  static const defaultLimit = 500;
  static const minLimit = 100;
  static const maxLimit = 5000;
  static const options = <int>[100, 500, 1000, 2000, 5000];

  const NotificationHistoryPolicy._();

  static int normalize(int? value) {
    return (value ?? defaultLimit).clamp(minLimit, maxLimit);
  }
}
