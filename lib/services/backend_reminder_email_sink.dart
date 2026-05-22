import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'reminder_sinks.dart';

/// Sends email reminder schedules to the authenticated Duoyi backend.
///
/// If the user is offline or not logged in, this sink degrades to no-op so
/// local push/alarm reminders are not affected by optional email delivery.
class BackendReminderEmailSink implements ReminderEmailSink {
  final ApiClient Function() _client;

  const BackendReminderEmailSink(this._client);

  @override
  Future<void> scheduleOnce({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
  }) async {
    final client = _client();
    if (!_canUse(client)) return;
    try {
      await client.post('/api/reminders/email/once', {
        'id': id,
        'title': title,
        'body': body,
        'when': when.toUtc().toIso8601String(),
        if (payload != null && payload.isNotEmpty) 'payload': payload,
      });
    } catch (e) {
      debugPrint('[BackendReminderEmailSink] scheduleOnce failed: $e');
    }
  }

  @override
  Future<void> scheduleRepeating({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    List<int>? weekdays,
    String? payload,
  }) async {
    final client = _client();
    if (!_canUse(client)) return;
    try {
      await client.post('/api/reminders/email/repeating', {
        'id': id,
        'title': title,
        'body': body,
        'hour': hour,
        'minute': minute,
        if (weekdays != null && weekdays.isNotEmpty) 'weekdays': weekdays,
        if (payload != null && payload.isNotEmpty) 'payload': payload,
      });
    } catch (e) {
      debugPrint('[BackendReminderEmailSink] scheduleRepeating failed: $e');
    }
  }

  @override
  Future<void> cancel(int id) async {
    final client = _client();
    if (!_canUse(client)) return;
    try {
      await client.delete('/api/reminders/email/$id');
    } catch (e) {
      debugPrint('[BackendReminderEmailSink] cancel failed: $e');
    }
  }

  bool _canUse(ApiClient client) =>
      client.token != null && client.token!.isNotEmpty;
}
