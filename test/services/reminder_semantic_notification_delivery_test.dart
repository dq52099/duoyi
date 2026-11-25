// The plugin interface is only used to restore its global registration in
// teardown; scheduling itself goes through the production singleton.
// ignore_for_file: depend_on_referenced_packages

import 'package:duoyi/core/app_brand.dart' show BrandStyle;
import 'package:duoyi/core/brand_strings.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/providers/notification_service.dart';
import 'package:duoyi/services/notification_action_envelope.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

const MethodChannel _localNotificationsChannel = MethodChannel(
  'dexterous.com/flutter/local_notifications',
);

String _twoDigits(int value) => value.toString().padLeft(2, '0');

String _wallClock(DateTime dateTime) =>
    '${dateTime.year.toString().padLeft(4, '0')}-'
    '${_twoDigits(dateTime.month)}-${_twoDigits(dateTime.day)}T'
    '${_twoDigits(dateTime.hour)}:${_twoDigits(dateTime.minute)}:'
    '${_twoDigits(dateTime.second)}';

int _weekdaySubId(int baseId, int weekday) {
  var hash = 0x811c9dc5;
  for (final unit in '$baseId:$weekday'.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash == 0 ? weekday : hash;
}

Map<String, Object?> _copyArguments(MethodCall call) =>
    Map<String, Object?>.from((call.arguments as Map).cast<String, Object?>());

bool _hasTarget(Map<String, Object?> args, String target) {
  final delivered = Uri.tryParse(args['payload'] as String? ?? '');
  final expected = Uri.parse(target);
  return delivered?.scheme == expected.scheme &&
      delivered?.host == expected.host && delivered?.path == expected.path;
}

Future<String?> _originalPayload(Map<String, Object?> args) async {
  final response = await NotificationActionEnvelope.verifyResponse(
    NotificationResponse(
      id: args['id'] as int,
      payload: args['payload'] as String?,
      notificationResponseType: NotificationResponseType.selectedNotification,
    ),
  );
  expect(response, isNotNull, reason: 'Scheduled payload must authenticate its actual notification ID.');
  return response!.payload;
}

String _habitBody({required AppLocale locale, required String title}) =>
    switch (locale) {
      AppLocale.zh => '别忘了: $title',
      AppLocale.en => "Don't forget: $title",
    };

({String title, String body}) _anniversaryCopy({
  required AppLocale locale,
  required String title,
  required int daysBefore,
}) => (
  title: locale == AppLocale.zh ? '📅 纪念日提醒' : '📅 Anniversary reminder',
  body: switch (locale) {
    AppLocale.zh => daysBefore == 0 ? '今天是 $title' : '$daysBefore 天后是 $title',
    AppLocale.en =>
      daysBefore == 0
          ? 'Today is $title'
          : '$title is in $daysBefore ${daysBefore == 1 ? 'day' : 'days'}.',
  },
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late AppLocale originalLocale;
  late TargetPlatform? originalTargetPlatformOverride;
  late Future<String?> Function()? originalSystemTimeZoneReader;
  late Future<String?> Function()? originalNativeTimeZoneReader;
  FlutterLocalNotificationsPlatform? originalPluginPlatform;
  NotificationService? service;
  final methodCalls = <MethodCall>[];
  final scheduleCalls = <Map<String, Object?>>[];
  final pending = <int, Map<String, Object?>>{};

  setUp(() async {
    originalLocale = I18n.current;
    originalTargetPlatformOverride = debugDefaultTargetPlatformOverride;
    originalSystemTimeZoneReader =
        LocalTimezoneResolver.debugSystemTimeZoneReader;
    originalNativeTimeZoneReader =
        LocalTimezoneResolver.debugNativeSystemTimeZoneReader;
    try {
      originalPluginPlatform = FlutterLocalNotificationsPlatform.instance;
    } on Error {
      originalPluginPlatform = null;
    }

    SharedPreferences.setMockInitialValues(<String, Object>{});
    methodCalls.clear();
    scheduleCalls.clear();
    pending.clear();
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    IOSFlutterLocalNotificationsPlugin.registerWith();
    LocalTimezoneResolver.debugSystemTimeZoneReader = () async =>
        'Asia/Shanghai';
    LocalTimezoneResolver.debugNativeSystemTimeZoneReader = () async => null;

    messenger.setMockMethodCallHandler(_localNotificationsChannel, (
      call,
    ) async {
      methodCalls.add(call);
      switch (call.method) {
        case 'zonedSchedule':
          final args = _copyArguments(call);
          scheduleCalls.add(args);
          final id = args['id']! as int;
          pending[id] = <String, Object?>{
            'id': id,
            'title': args['title'],
            'body': args['body'],
            'payload': args['payload'],
          };
          return null;
        case 'pendingNotificationRequests':
          return pending.values.toList(growable: false);
        case 'getNotificationAppLaunchDetails':
          return null;
        case 'cancel':
          pending.remove(call.arguments as int);
          return null;
        case 'cancelAll':
          pending.clear();
          return null;
        default:
          return null;
      }
    });

    service = NotificationService();
    await service!.init();
  });

  tearDown(() async {
    final disposedService = service;
    service = null;
    disposedService?.dispose();
    messenger.setMockMethodCallHandler(_localNotificationsChannel, null);
    if (originalPluginPlatform != null) {
      FlutterLocalNotificationsPlatform.instance = originalPluginPlatform!;
    }
    LocalTimezoneResolver.debugSystemTimeZoneReader =
        originalSystemTimeZoneReader;
    LocalTimezoneResolver.debugNativeSystemTimeZoneReader =
        originalNativeTimeZoneReader;
    debugDefaultTargetPlatformOverride = originalTargetPlatformOverride;
    I18n.setLocale(originalLocale);
    expect(I18n.current, originalLocale);
    expect(I18n.localeListenable.value, originalLocale);
  });

  test(
    'production habit and anniversary wrappers send localized copy and record it',
    () async {
      const brands = <(BrandStyle, String, String)>[
        (BrandStyle.defaultBrand, '习惯打卡提醒', 'Habit check-in reminder'),
        (BrandStyle.re0, '契约提醒', 'Pact Reminder'),
        (BrandStyle.liquidGlass, '习惯打卡提醒', 'Habit reminder'),
      ];
      const habitName = ' 早起 / Morning 🌅\n第二行 Keep going 🚀  ';
      const anniversaryTitle = ' 旅行纪念日 / Anniversary 🎈 ';
      const weekdays = <int>[2, 5];
      const reminderHour = 8;
      const reminderMinute = 17;

      await service!.runNotificationBatch(() async {
        for (final (style, zhHabitTitle, enHabitTitle) in brands) {
          for (final locale in AppLocale.values) {
            I18n.setLocale(locale);
            service!.setStrings(BrandStrings.forLocale(style, locale));
            final habitTitle = locale == AppLocale.zh
                ? zhHabitTitle
                : enHabitTitle;
            final habitBody = _habitBody(locale: locale, title: habitName);
            final suffix = '${style.name}-${locale.name}';

            final dailyHabitId = 'daily-$suffix';
            final dailyPayload = 'duoyi://habit/$dailyHabitId?confirm=1';
            final scheduleIndexBeforeDaily = scheduleCalls.length;
            await service!.scheduleHabitReminder(
              habitId: dailyHabitId,
              habitName: habitName,
              hour: reminderHour,
              minute: reminderMinute,
            );
            final dailyHistory = service!.history.singleWhere(
              (item) => item.relatedId == dailyHabitId,
            );
            final dailyCalls = scheduleCalls
                .skip(scheduleIndexBeforeDaily)
                .where((args) => _hasTarget(args, dailyPayload))
                .toList(growable: false);

            expect(dailyCalls, hasLength(1));
            final dailySchedule = dailyCalls.single;
            expect(dailySchedule['title'], habitTitle);
            expect(dailySchedule['body'], habitBody);
            expect(await _originalPayload(dailySchedule), dailyPayload);
            expect(
              dailySchedule['matchDateTimeComponents'],
              DateTimeComponents.time.index,
            );
            expect(dailySchedule['timeZoneName'], 'Asia/Shanghai');
            final dailyWallTime = DateTime.parse(
              dailySchedule['scheduledDateTime']! as String,
            );
            expect(dailyWallTime.hour, reminderHour);
            expect(dailyWallTime.minute, reminderMinute);
            expect(dailyHistory.id, dailySchedule['id'].toString());
            expect(dailyHistory.title, habitTitle);
            expect(dailyHistory.body, habitBody);
            expect(dailyHistory.type, NotificationType.habit);
            expect(dailyHistory.relatedId, dailyHabitId);
            expect(dailyHistory.isRead, isFalse);

            final weekdayHabitId = 'weekdays-$suffix';
            final weekdayPayload = 'duoyi://habit/$weekdayHabitId?confirm=1';
            final scheduleIndexBeforeWeekdays = scheduleCalls.length;
            await service!.scheduleHabitReminder(
              habitId: weekdayHabitId,
              habitName: habitName,
              hour: reminderHour,
              minute: reminderMinute,
              weekdays: weekdays,
            );
            final weekdayHistory = service!.history.singleWhere(
              (item) => item.relatedId == weekdayHabitId,
            );
            final weekdayCalls = scheduleCalls
                .skip(scheduleIndexBeforeWeekdays)
                .where((args) => _hasTarget(args, weekdayPayload))
                .toList(growable: false);
            final weekdayBaseId = int.parse(weekdayHistory.id);
            final expectedWeekdayIds = weekdays
                .map((weekday) => _weekdaySubId(weekdayBaseId, weekday))
                .toSet();

            expect(weekdayCalls, hasLength(weekdays.length));
            expect(
              weekdayCalls.map((args) => args['id']).toSet(),
              expectedWeekdayIds,
            );
            for (var index = 0; index < weekdayCalls.length; index++) {
              final args = weekdayCalls[index];
              final scheduledWallTime = DateTime.parse(
                args['scheduledDateTime']! as String,
              );
              final weekday = weekdays.singleWhere(
                (candidate) =>
                    args['id'] == _weekdaySubId(weekdayBaseId, candidate),
              );
              expect(args['title'], habitTitle);
              expect(args['body'], habitBody);
              expect(await _originalPayload(args), weekdayPayload);
              expect(
                args['matchDateTimeComponents'],
                DateTimeComponents.dayOfWeekAndTime.index,
              );
              expect(args['timeZoneName'], 'Asia/Shanghai');
              expect(scheduledWallTime.weekday, weekday);
              expect(scheduledWallTime.hour, reminderHour);
              expect(scheduledWallTime.minute, reminderMinute);
            }
            expect(weekdayHistory.id, weekdayBaseId.toString());
            expect(weekdayHistory.title, habitTitle);
            expect(weekdayHistory.body, habitBody);
            expect(weekdayHistory.type, NotificationType.habit);
            expect(weekdayHistory.relatedId, weekdayHabitId);
            expect(weekdayHistory.isRead, isFalse);
          }
        }

        final anniversaryDate = DateTime(2042, 9, 24);
        for (final locale in AppLocale.values) {
          I18n.setLocale(locale);
          for (final daysBefore in <int>[0, 1, 3]) {
            final annId = 'anniversary-${locale.name}-$daysBefore';
            final copy = _anniversaryCopy(
              locale: locale,
              title: anniversaryTitle,
              daysBefore: daysBefore,
            );
            final remindAt = DateTime(
              anniversaryDate.year,
              anniversaryDate.month,
              anniversaryDate.day,
              9,
              41,
            ).subtract(Duration(days: daysBefore));
            final scheduleIndex = scheduleCalls.length;
            await service!.scheduleAnniversary(
              annId: annId,
              title: anniversaryTitle,
              whenDate: anniversaryDate,
              daysBefore: daysBefore,
              hour: 9,
              minute: 41,
            );
            final history = service!.history.singleWhere(
              (item) => item.relatedId == annId,
            );
            final calls = scheduleCalls
                .skip(scheduleIndex)
                .toList(growable: false);

            expect(calls, hasLength(1));
            final args = calls.single;
            expect(args['title'], copy.title);
            expect(args['body'], copy.body);
            expect(await _originalPayload(args), 'duoyi://tab/calendar');
            expect(args['timeZoneName'], 'Asia/Shanghai');
            final scheduledAt = tz.TZDateTime.from(
              remindAt,
              tz.getLocation('Asia/Shanghai'),
            );
            expect(args['scheduledDateTime'], _wallClock(scheduledAt));
            expect(
              args['scheduledDateTimeISO8601'],
              scheduledAt.toIso8601String(),
            );
            expect(args.containsKey('matchDateTimeComponents'), isFalse);
            expect(history.id, args['id'].toString());
            expect(history.title, copy.title);
            expect(history.body, copy.body);
            expect(history.scheduledTime, remindAt);
            expect(history.type, NotificationType.anniversary);
            expect(history.relatedId, annId);
            expect(history.isRead, isFalse);
          }
        }
      });

      expect(scheduleCalls, hasLength(24));
      expect(methodCalls, isNotEmpty);
      expect(service!.history, hasLength(18));
      expect(service!.pendingCount, 18);
      expect(I18n.current, AppLocale.en);
    },
  );
}
