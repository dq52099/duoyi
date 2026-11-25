import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/account_preference_writes.dart';
import 'account_local_data_cleaner.dart';

/// A capability issued when scheduling, before an exported Activity can receive
/// a notification Intent. Action strings alone do not authenticate a callback.
class NotificationActionEnvelope {
  static const key = 'duoyi_notification_action_key_v1';
  static const _field = 'duoyi_notification_capability';
  static Future<void> _signTail = Future<void>.value();

  static Future<String?> signPayload(
    int id,
    String? payload, {
    Iterable<String> actions = const [],
    int? expectedAccountGeneration,
  }) {
    if (payload == null || payload.isEmpty) return Future.value(payload);
    final generation =
        expectedAccountGeneration ??
        AccountLocalDataCleaner.accountDataGeneration;
    final allowed = actions.toSet().toList()..sort();
    final previous = _signTail;
    final result = AccountPreferenceWrites.runResult<String?>((token) async {
      await previous;
      bool isCurrent() =>
          token.isCurrent &&
          AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation);
      if (!isCurrent()) throw const AccountPreferenceWriteCanceled();
      final prefs = await SharedPreferences.getInstance();
      if (!isCurrent()) throw const AccountPreferenceWriteCanceled();
      var secret = prefs.getString(key);
      if (secret == null) {
        final random = Random.secure();
        secret = base64Url.encode(
          List.generate(32, (_) => random.nextInt(256)),
        );
        final transaction = AccountPreferenceTransaction(prefs, isCurrent);
        try {
          await transaction.setString(key, secret);
          transaction.commit();
        } catch (error) {
          await transaction.rollback(canceledBeforeCleanup: true);
          rethrow;
        }
      }
      if (!isCurrent()) throw const AccountPreferenceWriteCanceled();
      final body = jsonEncode([
        1,
        id,
        payload,
        allowed,
        prefs.getString(AccountLocalDataCleaner.accountDataOwnerKey),
      ]);
      final encoded = base64Url.encode(utf8.encode(body));
      final signature = Hmac(
        sha256,
        base64Url.decode(secret),
      ).convert(utf8.encode(encoded)).toString();
      final uri = Uri.parse(payload);
      return uri
          .replace(
            queryParameters: {
              ...uri.queryParameters,
              _field: '$encoded.$signature',
            },
          )
          .toString();
    }, canceledResult: () => throw const AccountPreferenceWriteCanceled());
    _signTail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  static Future<NotificationResponse?> verifyResponse(
    NotificationResponse response,
  ) async {
    final generation = AccountLocalDataCleaner.accountDataGeneration;
    bool isCurrent() =>
        !AccountPreferenceWrites.isBoundaryActive &&
        AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation);
    if (!isCurrent()) return null;
    final payload = response.payload;
    if (payload == null) return null;
    try {
      final uri = Uri.parse(payload);
      final capability = uri.queryParameters[_field];
      if (capability == null) return null;
      final parts = capability.split('.');
      if (parts.length != 2) return null;
      final prefs = await SharedPreferences.getInstance();
      if (!isCurrent()) return null;
      // Receiving a forged response must never create an authenticating key.
      final secret = prefs.getString(key);
      if (secret == null) return null;
      final expected = Hmac(
        sha256,
        base64Url.decode(secret),
      ).convert(utf8.encode(parts[0])).toString();
      if (!_equalSignature(expected, parts[1])) return null;
      final body = jsonDecode(utf8.decode(base64Url.decode(parts[0])));
      if (body is! List ||
          body.length != 5 ||
          body[0] != 1 ||
          body[1] != response.id ||
          body[2] is! String ||
          body[3] is! List ||
          body[4] !=
              prefs.getString(AccountLocalDataCleaner.accountDataOwnerKey)) {
        return null;
      }
      final original = body[2] as String;
      final originalUri = Uri.parse(original);
      final reconstructed = originalUri.replace(
        queryParameters: {...originalUri.queryParameters, _field: capability},
      );
      if (uri != reconstructed) return null;
      final action = response.actionId;
      if (action != null && action.isNotEmpty && !body[3].contains(action)) {
        return null;
      }
      if (!isCurrent()) return null;
      return NotificationResponse(
        id: response.id,
        actionId: response.actionId,
        input: response.input,
        payload: original,
        notificationResponseType: response.notificationResponseType,
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  static bool _equalSignature(String expected, String actual) {
    var difference = expected.length ^ actual.length;
    for (var i = 0; i < expected.length; i++) {
      difference |=
          expected.codeUnitAt(i) ^
          (i < actual.length ? actual.codeUnitAt(i) : 0);
    }
    return difference == 0;
  }
}
