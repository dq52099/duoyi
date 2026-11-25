import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/services/alarm_service.dart';
import 'package:duoyi/services/local_notifications_io.dart';
import 'package:duoyi/services/native_reminder_ringtone.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _ringtoneChannel = MethodChannel('duoyi/reminder_ringtone');

Matcher _strictCancellationError() => isA<NativeReminderRingtoneException>()
    .having((error) => error.method, 'method', 'cancelAll');

Matcher _alarmCancellationError() => isA<AlarmQueueHandoffException>();

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late bool? originalAndroidOverride;
  late Future<String?> Function()? originalSystemTimeZoneReader;
  late List<String> calls;
  late _CancelAllOnlyPlugin plugin;
  Object? nativeResult;
  PlatformException? nativeFailure;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    originalSystemTimeZoneReader =
        LocalTimezoneResolver.debugSystemTimeZoneReader;
    LocalTimezoneResolver.debugSystemTimeZoneReader = () async =>
        'Europe/London';
    originalAndroidOverride = NativeReminderRingtone.debugIsAndroidOverride;
    NativeReminderRingtone.debugIsAndroidOverride = true;
    calls = <String>[];
    plugin = _CancelAllOnlyPlugin(calls);
    nativeResult = null;
    nativeFailure = null;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(_ringtoneChannel, (
      call,
    ) async {
      expect(call.method, 'cancelAll');
      expect(call.arguments, isNull);
      calls.add('native:cancelAll');
      final failure = nativeFailure;
      if (failure != null) throw failure;
      return nativeResult;
    });
  });

  tearDown(() {
    LocalTimezoneResolver.debugSystemTimeZoneReader =
        originalSystemTimeZoneReader;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _ringtoneChannel,
      null,
    );
    NativeReminderRingtone.debugIsAndroidOverride = originalAndroidOverride;
  });

  void expectBothOwners() {
    expect(calls, <String>['plugin:cancelAll', 'native:cancelAll']);
    expect(plugin.cancelAllCalls, 1);
  }

  PlatformException nativePlatformError() => PlatformException(
    code: 'test_native_cancel_all_failed',
    message: 'Synthetic native queue cancellation failure',
  );

  LocalNotifications localNotifications() =>
      LocalNotifications.forTesting(plugin: plugin, isAndroid: true);

  AlarmService alarmService() => AlarmService.forTesting(plugin: plugin);

  test('strict native cancelAll rejects false platform result', () async {
    nativeResult = false;
    await expectLater(
      NativeReminderRingtone.cancelAllOrThrow(),
      throwsA(_strictCancellationError()),
    );
    expect(calls, <String>['native:cancelAll']);
    expect(plugin.cancelAllCalls, 0);
  });

  test('strict native cancelAll wraps platform channel failure', () async {
    nativeFailure = nativePlatformError();
    await expectLater(
      NativeReminderRingtone.cancelAllOrThrow(),
      throwsA(_strictCancellationError()),
    );
    expect(calls, <String>['native:cancelAll']);
    expect(plugin.cancelAllCalls, 0);
  });

  test('strict native cancelAll accepts null platform success', () async {
    await NativeReminderRingtone.cancelAllOrThrow();
    expect(calls, <String>['native:cancelAll']);
    expect(plugin.cancelAllCalls, 0);
  });

  test(
    'best effort native cancelAll preserves false result compatibility',
    () async {
      nativeResult = false;
      await NativeReminderRingtone.cancelAll();
      expect(calls, <String>['native:cancelAll']);
      expect(plugin.cancelAllCalls, 0);
    },
  );

  test(
    'best effort native cancelAll preserves platform error compatibility',
    () async {
      nativeFailure = nativePlatformError();
      await NativeReminderRingtone.cancelAll();
      expect(calls, <String>['native:cancelAll']);
      expect(plugin.cancelAllCalls, 0);
    },
  );

  test(
    'LocalNotifications cancelAll surfaces native false after plugin success',
    () async {
      nativeResult = false;
      await expectLater(
        localNotifications().cancelAll(),
        throwsA(_strictCancellationError()),
      );
      expectBothOwners();
    },
  );

  test(
    'LocalNotifications cancelAll surfaces native platform error after plugin success',
    () async {
      nativeFailure = nativePlatformError();
      await expectLater(
        localNotifications().cancelAll(),
        throwsA(_strictCancellationError()),
      );
      expectBothOwners();
    },
  );

  test(
    'LocalNotifications cancelAll accepts plugin and native success',
    () async {
      await localNotifications().cancelAll();
      expectBothOwners();
    },
  );

  test(
    'LocalNotifications cancelAll still calls native after plugin failure',
    () async {
      final pluginFailure = StateError('Synthetic plugin queue failure');
      plugin.failure = pluginFailure;
      await expectLater(
        localNotifications().cancelAll(),
        throwsA(same(pluginFailure)),
      );
      expectBothOwners();
    },
  );

  test(
    'LocalNotifications cancelAll preserves first plugin error when both owners fail',
    () async {
      final pluginFailure = StateError('Synthetic first plugin queue failure');
      plugin.failure = pluginFailure;
      nativeFailure = nativePlatformError();
      await expectLater(
        localNotifications().cancelAll(),
        throwsA(same(pluginFailure)),
      );
      expectBothOwners();
    },
  );

  test(
    'AlarmService cancelAll wraps native false after plugin success',
    () async {
      nativeResult = false;
      final alarm = alarmService();
      await expectLater(alarm.cancelAll(), throwsA(_alarmCancellationError()));
      expectBothOwners();
      expect(alarm.lastScheduleIssue, isNotNull);
    },
  );

  test(
    'AlarmService cancelAll wraps native platform error after plugin success',
    () async {
      nativeFailure = nativePlatformError();
      final alarm = alarmService();
      await expectLater(alarm.cancelAll(), throwsA(_alarmCancellationError()));
      expectBothOwners();
      expect(alarm.lastScheduleIssue, isNotNull);
    },
  );

  test('AlarmService cancelAll accepts plugin and native success', () async {
    final alarm = alarmService();
    await alarm.cancelAll();
    expectBothOwners();
    expect(alarm.lastScheduleIssue, isNull);
  });

  test(
    'AlarmService cancelAll still calls native after plugin failure',
    () async {
      plugin.failure = StateError('Synthetic plugin queue failure');
      final alarm = alarmService();
      await expectLater(alarm.cancelAll(), throwsA(_alarmCancellationError()));
      expectBothOwners();
      expect(alarm.lastScheduleIssue, isNotNull);
    },
  );

  test(
    'AlarmService cancelAll wraps both owner failures after trying both',
    () async {
      plugin.failure = StateError('Synthetic first plugin queue failure');
      nativeFailure = nativePlatformError();
      final alarm = alarmService();
      await expectLater(alarm.cancelAll(), throwsA(_alarmCancellationError()));
      expectBothOwners();
      expect(alarm.lastScheduleIssue, isNotNull);
    },
  );

  test(
    'LocalNotifications cancelAll clears both queues after initialization failure',
    () async {
      final initializationFailure = StateError(
        'Synthetic plugin initialization failure',
      );
      plugin.initializationFailure = initializationFailure;
      final notifications = LocalNotifications.forTesting(
        plugin: plugin,
        isAndroid: true,
        initialized: false,
      );
      await expectLater(
        notifications.cancelAll(),
        throwsA(same(initializationFailure)),
      );
      expect(calls, <String>[
        'plugin:initialize',
        'plugin:cancelAll',
        'native:cancelAll',
      ]);
      expect(plugin.cancelAllCalls, 1);
    },
  );

  test(
    'LocalNotifications cancelAll preserves initialization error when all cleanup stages fail',
    () async {
      final initializationFailure = StateError(
        'Synthetic first initialization failure',
      );
      plugin.initializationFailure = initializationFailure;
      plugin.failure = StateError(
        'Synthetic subsequent plugin cancellation failure',
      );
      nativeFailure = nativePlatformError();
      final notifications = LocalNotifications.forTesting(
        plugin: plugin,
        isAndroid: true,
        initialized: false,
      );
      await expectLater(
        notifications.cancelAll(),
        throwsA(same(initializationFailure)),
      );
      expect(calls, <String>[
        'plugin:initialize',
        'plugin:cancelAll',
        'native:cancelAll',
      ]);
      expect(plugin.cancelAllCalls, 1);
    },
  );

  test(
    'AlarmService cancelAll clears both queues after initialization failure',
    () async {
      plugin.initializationFailure = StateError(
        'Synthetic plugin initialization failure',
      );
      final alarm = AlarmService.forTesting(plugin: plugin, initialized: false);
      await expectLater(alarm.cancelAll(), throwsA(_alarmCancellationError()));
      expect(calls, <String>[
        'plugin:initialize',
        'plugin:cancelAll',
        'native:cancelAll',
      ]);
      expect(plugin.cancelAllCalls, 1);
      expect(alarm.lastScheduleIssue, isNotNull);
      expect(alarm.isInitialized, isFalse);
    },
  );

  test(
    'AlarmService cancelAll reports failure after all initialization and cleanup stages fail',
    () async {
      plugin.initializationFailure = StateError(
        'Synthetic first initialization failure',
      );
      plugin.failure = StateError(
        'Synthetic subsequent plugin cancellation failure',
      );
      nativeFailure = nativePlatformError();
      final alarm = AlarmService.forTesting(plugin: plugin, initialized: false);
      await expectLater(alarm.cancelAll(), throwsA(_alarmCancellationError()));
      expect(calls, <String>[
        'plugin:initialize',
        'plugin:cancelAll',
        'native:cancelAll',
      ]);
      expect(plugin.cancelAllCalls, 1);
      expect(alarm.lastScheduleIssue, isNotNull);
      expect(alarm.isInitialized, isFalse);
    },
  );
}

class _CancelAllOnlyPlugin extends Fake
    implements FlutterLocalNotificationsPlugin {
  _CancelAllOnlyPlugin(this.calls);

  final List<String> calls;
  Object? failure;
  Object? initializationFailure;
  int cancelAllCalls = 0;

  @override
  Future<bool?> initialize(
    InitializationSettings initializationSettings, {
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
    onDidReceiveBackgroundNotificationResponse,
  }) async {
    calls.add('plugin:initialize');
    final error = initializationFailure;
    if (error != null) throw error;
    return true;
  }

  @override
  Future<void> cancelAll() async {
    cancelAllCalls++;
    calls.add('plugin:cancelAll');
    final error = failure;
    if (error != null) throw error;
  }
}
