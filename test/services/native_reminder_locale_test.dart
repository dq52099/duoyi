import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/services/native_reminder_ringtone.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('duoyi/reminder_ringtone');
const _title = '原始 reminder title / 保持原样';
const _body = 'Body text — keep every character 原文不变';
const _payload = 'reminder://原始/payload?keep=this';
final _when = DateTime.utc(2031, 4, 5, 6, 7, 8);
const _weekdays = <int>[1, 3, 7];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  late AppLocale previousLocale;
  int? pendingId;

  setUp(() {
    previousLocale = I18n.current;
    I18n.setLocale(AppLocale.zh);
    NativeReminderRingtone.debugIsAndroidOverride = true;
    calls.clear();
    pendingId = null;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      if (call.method == 'pendingIds') {
        return pendingId == null ? const <int>[] : <int>[pendingId!];
      }
      if (call.method == 'scheduleOnce' || call.method == 'scheduleDaily') {
        pendingId = (call.arguments! as Map<Object?, Object?>)['id'] as int;
      }
      return true;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(_channel, null);
    NativeReminderRingtone.debugIsAndroidOverride = null;
    I18n.setLocale(previousLocale);
  });

  for (final method in <String>['showNow', 'scheduleOnce', 'scheduleDaily']) {
    test(
      '$method forwards explicit and current locales through the bridge',
      () async {
        for (final scenario in _localeScenarios) {
          final id = 7300 + calls.length;
          I18n.setLocale(scenario.currentLocale);
          final firstCallIndex = calls.length;

          await _invoke(method, id, scenario);

          final invocation = calls
              .skip(firstCallIndex)
              .firstWhere((call) => call.method == method);
          expect(
            invocation.arguments,
            _expectedArguments(method, id, scenario.expectedLocale),
            reason: '${scenario.description} should be encoded on $method.',
          );

          if (method == 'scheduleOnce' || method == 'scheduleDaily') {
            final followupCalls = calls.skip(firstCallIndex).toList();
            expect(
              followupCalls.map((call) => call.method),
              contains('pendingIds'),
            );
            expect(
              await NativeReminderRingtone.pendingIdsOrThrow(),
              contains(id),
            );
          }
        }
      },
    );
  }
}

const _localeScenarios = <_LocaleScenario>[
  _LocaleScenario(
    description: 'explicit zh',
    currentLocale: AppLocale.en,
    argumentLocale: AppLocale.zh,
    expectedLocale: AppLocale.zh,
  ),
  _LocaleScenario(
    description: 'explicit en',
    currentLocale: AppLocale.zh,
    argumentLocale: AppLocale.en,
    expectedLocale: AppLocale.en,
  ),
  _LocaleScenario(
    description: 'omitted locale with current zh',
    currentLocale: AppLocale.zh,
    expectedLocale: AppLocale.zh,
  ),
  _LocaleScenario(
    description: 'omitted locale with current en',
    currentLocale: AppLocale.en,
    expectedLocale: AppLocale.en,
  ),
];

class _LocaleScenario {
  const _LocaleScenario({
    required this.description,
    required this.currentLocale,
    required this.expectedLocale,
    this.argumentLocale,
  });

  final String description;
  final AppLocale currentLocale;
  final AppLocale? argumentLocale;
  final AppLocale expectedLocale;

  bool get passesLocaleArgument => argumentLocale != null;
}

Future<void> _invoke(String method, int id, _LocaleScenario scenario) {
  switch (method) {
    case 'showNow':
      if (scenario.passesLocaleArgument) {
        return NativeReminderRingtone.showNow(
          id: id,
          title: _title,
          body: _body,
          payload: _payload,
          fullScreen: true,
          vibrate: false,
          snoozeMinutes: 7,
          repeatCount: 2,
          locale: scenario.argumentLocale,
        );
      }
      return NativeReminderRingtone.showNow(
        id: id,
        title: _title,
        body: _body,
        payload: _payload,
        fullScreen: true,
        vibrate: false,
        snoozeMinutes: 7,
        repeatCount: 2,
      );
    case 'scheduleOnce':
      if (scenario.passesLocaleArgument) {
        return NativeReminderRingtone.scheduleOnce(
          id: id,
          title: _title,
          body: _body,
          when: _when,
          payload: _payload,
          fullScreen: true,
          vibrate: false,
          snoozeMinutes: 7,
          repeatCount: 2,
          locale: scenario.argumentLocale,
        );
      }
      return NativeReminderRingtone.scheduleOnce(
        id: id,
        title: _title,
        body: _body,
        when: _when,
        payload: _payload,
        fullScreen: true,
        vibrate: false,
        snoozeMinutes: 7,
        repeatCount: 2,
      );
    case 'scheduleDaily':
      if (scenario.passesLocaleArgument) {
        return NativeReminderRingtone.scheduleDaily(
          id: id,
          title: _title,
          body: _body,
          hour: 6,
          minute: 45,
          weekdays: _weekdays,
          payload: _payload,
          fullScreen: true,
          vibrate: false,
          snoozeMinutes: 7,
          repeatCount: 2,
          locale: scenario.argumentLocale,
        );
      }
      return NativeReminderRingtone.scheduleDaily(
        id: id,
        title: _title,
        body: _body,
        hour: 6,
        minute: 45,
        weekdays: _weekdays,
        payload: _payload,
        fullScreen: true,
        vibrate: false,
        snoozeMinutes: 7,
        repeatCount: 2,
      );
    default:
      throw ArgumentError.value(method, 'method', 'Unknown bridge method');
  }
}

Map<String, Object?> _expectedArguments(
  String method,
  int id,
  AppLocale locale,
) {
  final result = <String, Object?>{
    'id': id,
    'title': _title,
    'body': _body,
    'payload': _payload,
    'fullScreen': true,
    'vibrate': false,
    'snoozeMinutes': 7,
    'repeatCount': 2,
    'locale': locale.storageValue,
  };
  if (method == 'scheduleOnce') {
    result['triggerAtMillis'] = _when.millisecondsSinceEpoch;
  } else if (method == 'scheduleDaily') {
    result['hour'] = 6;
    result['minute'] = 45;
    result['weekdays'] = _weekdays;
    result['timezoneId'] = LocalTimezoneResolver.currentIana;
  }
  return result;
}
