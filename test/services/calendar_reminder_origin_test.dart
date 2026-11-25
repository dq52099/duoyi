// Scheduling uses the production singleton and plugin MethodChannel.
// ignore_for_file: depend_on_referenced_packages
import 'dart:async';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/providers/notification_service.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _channel = MethodChannel('dexterous.com/flutter/local_notifications');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late TargetPlatform? oldTarget;
  FlutterLocalNotificationsPlatform? oldPlatform;
  late Future<String?> Function()? oldTimezoneReader;
  late Future<String?> Function()? oldNativeTimezoneReader;
  late NotificationService service;
  Completer<void>? started;
  Completer<void>? release;
  var throwAfterRelease = false;
  final pendingNative = <int, Map<String, Object?>>{};
  final cancelled = <int>[];
  final when = DateTime(2100, 1, 1, 15);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    oldTarget = debugDefaultTargetPlatformOverride;
    try {
      oldPlatform = FlutterLocalNotificationsPlatform.instance;
    } on Error {
      oldPlatform = null;
    }
    oldTimezoneReader = LocalTimezoneResolver.debugSystemTimeZoneReader;
    oldNativeTimezoneReader =
        LocalTimezoneResolver.debugNativeSystemTimeZoneReader;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    IOSFlutterLocalNotificationsPlugin.registerWith();
    LocalTimezoneResolver.debugSystemTimeZoneReader = () async =>
        'Asia/Shanghai';
    LocalTimezoneResolver.debugNativeSystemTimeZoneReader = () async => null;
    started = null;
    release = null;
    throwAfterRelease = false;
    pendingNative.clear();
    cancelled.clear();
    messenger.setMockMethodCallHandler(_channel, (call) async {
      switch (call.method) {
        case 'zonedSchedule':
          final args = Map<String, Object?>.from(call.arguments as Map);
          final id = args['id']! as int;
          final currentGate = release;
          if (currentGate != null && !started!.isCompleted) {
            started!.complete();
            await currentGate.future;
            if (throwAfterRelease) {
              throw PlatformException(code: 'private-old-diagnostic');
            }
          }
          pendingNative[id] = {
            'id': id,
            'title': args['title'],
            'body': args['body'],
            'payload': args['payload'],
          };
          return null;
        case 'pendingNotificationRequests':
          return pendingNative.values.toList();
        case 'cancel':
          final id = call.arguments as int;
          cancelled.add(id);
          pendingNative.remove(id);
          return null;
        case 'cancelAll':
          pendingNative.clear();
          return null;
        default:
          return null;
      }
    });
    service = NotificationService();
    await service.init();
  });
  tearDown(() {
    service.dispose();
    messenger.setMockMethodCallHandler(_channel, null);
    if (oldPlatform != null) {
      FlutterLocalNotificationsPlatform.instance = oldPlatform!;
    }
    debugDefaultTargetPlatformOverride = oldTarget;
    LocalTimezoneResolver.debugSystemTimeZoneReader = oldTimezoneReader;
    LocalTimezoneResolver.debugNativeSystemTimeZoneReader =
        oldNativeTimezoneReader;
  });

  test(
    'current calendar registration records one native reminder and history',
    () async {
      await service.scheduleCalendarReminder(
        calendarEventId: 'current',
        title: 'Reminder',
        body: 'Literal / 原文',
        when: when,
        canContinue: () => true,
      );
      expect(pendingNative, hasLength(1));
      expect(service.history.single.body, 'Literal / 原文');
      expect(service.history.single.relatedId, 'current');
      expect(service.pendingCount, 1);
    },
  );

  test(
    'replacement of the same event waits for stale native compensation',
    () async {
      var oldCurrent = true;
      started = Completer<void>();
      release = Completer<void>();
      final old = service.scheduleCalendarReminder(
        calendarEventId: 'same',
        title: 'Old',
        body: 'Old account text',
        when: when,
        canContinue: () => oldCurrent,
      );
      final oldResult = old.then<Object?>(
        (_) => null,
        onError: (Object error) => error,
      );
      await started!.future;
      oldCurrent = false;
      var newCompleted = false;
      final replacement = service
          .scheduleCalendarReminder(
            calendarEventId: 'same',
            title: 'New',
            body: 'New account text',
            when: when,
            canContinue: () => true,
          )
          .then((_) => newCompleted = true);
      await Future<void>.delayed(Duration.zero);
      expect(newCompleted, isFalse);
      release!.complete();
      expect(await oldResult, isA<AccountPreferenceWriteCanceled>());
      await replacement;
      expect(pendingNative, hasLength(1));
      expect(pendingNative.values.single['body'], 'New account text');
      expect(service.history.single.body, 'New account text');
      expect(service.pendingCount, 1);
      expect(service.lastScheduleIssue, isNull);
    },
  );

  for (final granted in [false, true]) {
    test(
      'stale permission preflight granted=$granted cannot record an old issue',
      () async {
        final preflight = _HeldPermissionService();
        addTearDown(preflight.dispose);
        var current = true;
        final pending = preflight.ensureReadyForReminder(
          scheduledTime: when,
          relatedId: 'old',
          canContinue: () => current,
        );
        await preflight.started.future;
        current = false;
        preflight.release.complete(granted);
        expect(await pending, isFalse);
        expect(preflight.history, isEmpty);
        expect(preflight.lastScheduleIssue, isNull);
      },
    );
  }

  test(
    'explicit cancellation revokes a held registration before finishing',
    () async {
      started = Completer<void>();
      release = Completer<void>();
      final old = service.scheduleCalendarReminder(
        calendarEventId: 'cancelled',
        title: 'Old',
        body: 'Old account text',
        when: when,
      );
      final oldResult = old.then<Object?>(
        (_) => null,
        onError: (Object error) => error,
      );
      await started!.future;
      var cancelCompleted = false;
      final cancellation = service
          .cancelCalendarReminder('cancelled')
          .then((_) => cancelCompleted = true);
      await Future<void>.delayed(Duration.zero);
      expect(cancelCompleted, isFalse);
      release!.complete();
      expect(await oldResult, isA<AccountPreferenceWriteCanceled>());
      await cancellation;
      expect(pendingNative, isEmpty);
      expect(service.history, isEmpty);
      expect(service.pendingCount, 0);
      expect(service.lastScheduleIssue, isNull);
      await service.scheduleCalendarReminder(
        calendarEventId: 'cancelled',
        title: 'New',
        body: 'New account text',
        when: when,
      );
      expect(pendingNative.values.single['body'], 'New account text');
      expect(service.history.single.body, 'New account text');
    },
  );

  for (final invalidate in ['lease', 'reset', 'accountGeneration']) {
    for (final fails in [false, true]) {
      test(
        'held native $invalidate fails=$fails cannot republish old reminder',
        () async {
          var current = true;
          started = Completer<void>();
          release = Completer<void>();
          throwAfterRelease = fails;
          final oldCall = service.scheduleCalendarReminder(
            calendarEventId: 'old',
            title: 'Old title',
            body: 'Old account text',
            when: when,
            canContinue: () => current,
          );
          final result = oldCall.then<Object?>(
            (_) => null,
            onError: (Object error) => error,
          );
          await started!.future;
          switch (invalidate) {
            case 'lease':
              current = false;
            case 'reset':
              service.resetLocalState();
            case 'accountGeneration':
              AccountLocalDataCleaner.invalidateInFlightAccountWrites();
          }
          await LocalNotifications.instance.cancelAll();
          await service.scheduleCalendarReminder(
            calendarEventId: 'new',
            title: 'New title',
            body: 'New account text',
            when: when,
            canContinue: () => true,
          );
          final newId = pendingNative.keys.single;
          release!.complete();
          expect(await result, isA<AccountPreferenceWriteCanceled>());
          expect(pendingNative.keys, [newId]);
          expect(pendingNative.values.single['body'], 'New account text');
          expect(service.history, hasLength(1));
          expect(service.history.single.relatedId, 'new');
          expect(service.pendingCount, 1);
          expect(service.lastScheduleIssue, isNull);
          expect(
            cancelled.where((id) => id == newId),
            hasLength(1),
            reason: 'Only the pre-registration replacement cancels the new ID',
          );
        },
      );
    }
  }
}

class _HeldPermissionService extends NotificationService {
  final started = Completer<void>();
  final release = Completer<bool>();
  @override
  Future<bool> requestPermission({bool Function()? canContinue}) async {
    started.complete();
    return release.future;
  }
}
