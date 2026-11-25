// ignore_for_file: depend_on_referenced_packages

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/local_notifications.dart';
import 'package:duoyi/services/notification_action_envelope.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

const _channel = MethodChannel('dexterous.com/flutter/local_notifications');
const _ownerKey = AccountLocalDataCleaner.accountDataOwnerKey;
const _notificationId = 421;
const _todoId = 'synthetic-cold-todo';
const _payload = 'duoyi://todo/$_todoId';
const _action = 'todo_complete_$_todoId';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The production notification service caches initialization and its launch
  // probe process-wide. Keep this file to one cold initialization scenario.
  test('cached cold notification is discarded after an account switch', () async {
    await AccountPreferenceWrites.drain();
    final originalTarget = debugDefaultTargetPlatformOverride;
    final originalStore = SharedPreferencesStorePlatform.instance;
    final originalDebugPrint = debugPrint;
    FlutterLocalNotificationsPlatform? originalPluginPlatform;
    try {
      originalPluginPlatform = FlutterLocalNotificationsPlatform.instance;
    } on Error {
      originalPluginPlatform = null;
    }
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final methods = <String>[];
    final diagnostics = <String>[];

    addTearDown(() async {
      await AccountPreferenceWrites.drain();
      messenger.setMockMethodCallHandler(_channel, null);
      if (originalPluginPlatform != null) {
        FlutterLocalNotificationsPlatform.instance = originalPluginPlatform;
      }
      debugDefaultTargetPlatformOverride = originalTarget;
      debugPrint = originalDebugPrint;
      SharedPreferences.setMockInitialValues(<String, Object>{});
      SharedPreferencesStorePlatform.instance = originalStore;
    });

    SharedPreferences.setMockInitialValues(<String, Object>{
      _ownerKey: 'synthetic-cold-account-A',
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    debugPrint = (message, {wrapWidth}) {
      if (message != null) diagnostics.add(message);
    };

    final generation = AccountLocalDataCleaner.accountDataGeneration;
    final signed = await NotificationActionEnvelope.signPayload(
      _notificationId,
      _payload,
      actions: const [_action],
      expectedAccountGeneration: generation,
    );
    expect(signed, isNotNull);
    final response = NotificationResponse(
      id: _notificationId,
      actionId: _action,
      payload: signed,
      notificationResponseType:
          NotificationResponseType.selectedNotificationAction,
    );
    final notifications = LocalNotifications.instance;
    // Establish that this exact signed response is accepted and maps to an
    // automatic action before the real cold probe caches its mapped payload.
    expect(
      await notifications.payloadForNotificationResponse(response),
      'duoyi://action/complete_todo?id=$_todoId',
    );

    messenger.setMockMethodCallHandler(_channel, (call) async {
      methods.add(call.method);
      switch (call.method) {
        case 'initialize':
          return true;
        case 'getNotificationAppLaunchDetails':
          return <String, Object?>{
            'notificationLaunchedApp': true,
            'notificationResponse': <String, Object?>{
              'notificationId': _notificationId,
              'actionId': _action,
              'payload': signed,
              'notificationResponseType':
                  NotificationResponseType.selectedNotificationAction.index,
            },
          };
        default:
          throw StateError('Unexpected notification channel call: ${call.method}');
      }
    });

    await notifications.initForLaunchPayload();
    expect(methods, ['initialize', 'getNotificationAppLaunchDetails']);
    expect(diagnostics, isEmpty, reason: 'the actual cold probe must succeed');
    expect(
      AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation),
      isTrue,
    );

    final prefs = await SharedPreferences.getInstance();
    final signingKey = prefs.getString(NotificationActionEnvelope.key);
    expect(signingKey, isNotNull);
    AccountLocalDataCleaner.invalidateInFlightAccountWrites();
    expect(await prefs.setString(_ownerKey, 'synthetic-cold-account-B'), isTrue);
    // Do not delete the key or reverify the response. The accepted action is
    // already cached; taking it must enforce the saved account generation.
    expect(prefs.getString(NotificationActionEnvelope.key), signingKey);
    expect(notifications.takeLaunchPayload(), isNull);
    expect(notifications.takeLaunchPayload(), isNull);
    expect(methods, ['initialize', 'getNotificationAppLaunchDetails']);
  });
}
