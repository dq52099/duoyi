import 'package:flutter_test/flutter_test.dart';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/goal.dart' show ReminderKind;
import 'package:duoyi/services/reminder_schedule_display_copy.dart';

const _maxSafeJsonInteger = 9007199254740991;

Map<String, Object?> _registeredJson({
  Object? schemaVersion = 1,
  Object? shape = 'registered',
  Object? subject = 'todo',
  Object? titleMode = 'default',
}) => {
  'schemaVersion': schemaVersion,
  'shape': shape,
  'subject': subject,
  'titleMode': titleMode,
};

Map<String, Object?> _rulesJson({
  Object? schemaVersion = 1,
  Object? shape = 'rules',
  Object? subject = 'todo',
  Object? titleMode = 'literal',
  Object? repeating = false,
  Object? ruleCount = 2,
}) => {
  'schemaVersion': schemaVersion,
  'shape': shape,
  'subject': subject,
  'titleMode': titleMode,
  'repeating': repeating,
  'ruleCount': ruleCount,
};

Map<String, Object?> _habitJson({
  Object? schemaVersion = 1,
  Object? shape = 'habit',
  Object? subject = 'habit',
  Object? titleMode = 'literal',
  Object? primaryKind = 'push',
  Object? weekdays = const <int>[1, 3],
  Object? hour = 7,
  Object? minute = 0,
}) => {
  'schemaVersion': schemaVersion,
  'shape': shape,
  'subject': subject,
  'titleMode': titleMode,
  'primaryKind': primaryKind,
  'weekdays': weekdays,
  'hour': hour,
  'minute': minute,
};

Map<String, Object?> _datedJson({
  Object? schemaVersion = 1,
  Object? shape = 'dated',
  Object? subject = 'anniversary',
  Object? titleMode = 'literal',
  Object? primaryKind = 'alarm',
  Object? year = 2028,
  Object? month = 2,
  Object? day = 29,
  Object? hour = 7,
  Object? minute = 5,
}) => {
  'schemaVersion': schemaVersion,
  'shape': shape,
  'subject': subject,
  'titleMode': titleMode,
  'primaryKind': primaryKind,
  'year': year,
  'month': month,
  'day': day,
  'hour': hour,
  'minute': minute,
};

ReminderScheduleDisplayCopy? _parse(
  Object? json, {
  String objectType = 'todo',
}) => ReminderScheduleDisplayCopy.tryFromJson(json, objectType: objectType);

void _expectNull(Object? json, {String objectType = 'todo'}) {
  expect(_parse(json, objectType: objectType), isNull, reason: '$json');
}

void main() {
  group('ReminderScheduleDisplayCopy serialization and rendering', () {
    test(
      'registered records round-trip and localize every supported subject',
      () {
        const zhSubjects = <ReminderScheduleSubject, String>{
          ReminderScheduleSubject.todo: '待办',
          ReminderScheduleSubject.goal: '目标',
          ReminderScheduleSubject.habit: '日常',
          ReminderScheduleSubject.anniversary: '纪念日',
          ReminderScheduleSubject.countdown: '倒数日',
        };
        const enSubjects = <ReminderScheduleSubject, String>{
          ReminderScheduleSubject.todo: 'Todo',
          ReminderScheduleSubject.goal: 'Goal',
          ReminderScheduleSubject.habit: 'Habit',
          ReminderScheduleSubject.anniversary: 'Anniversary',
          ReminderScheduleSubject.countdown: 'Countdown',
        };

        for (final entry in zhSubjects.entries) {
          final copy = ReminderScheduleDisplayCopy.registered(entry.key);
          final json = copy.toJson();
          expect(json.keys.toSet(), <String>{
            'schemaVersion',
            'shape',
            'subject',
            'titleMode',
          });
          expect(json, <String, Object?>{
            'schemaVersion': 1,
            'shape': 'registered',
            'subject': entry.key.name,
            'titleMode': 'default',
          });

          final decoded = _parse(json, objectType: entry.key.name)!;
          expect(decoded.toJson(), equals(json));

          final zh = decoded.render(
            title: 'stored title',
            subtitle: 'stored subtitle',
            kinds: const <ReminderKind>{},
            locale: AppLocale.zh,
          );
          final en = decoded.render(
            title: 'stored title',
            subtitle: 'stored subtitle',
            kinds: const <ReminderKind>{},
            locale: AppLocale.en,
          );
          expect(zh.title, '${entry.value}提醒');
          expect(en.title, '${enSubjects[entry.key]} reminder');
          expect(zh.subtitle, '${entry.value} · 已登记到系统提醒队列');
          expect(
            en.subtitle,
            '${enSubjects[entry.key]} · Registered with the system reminder queue',
          );
        }
      },
    );

    test(
      'rules records preserve literal titles and render locale-specific facts',
      () {
        final copy = ReminderScheduleDisplayCopy.rules(
          ReminderScheduleSubject.todo,
          defaultTitle: false,
          repeating: false,
          ruleCount: 2,
        );
        final json = copy.toJson();
        expect(json.keys.toSet(), <String>{
          'schemaVersion',
          'shape',
          'subject',
          'titleMode',
          'repeating',
          'ruleCount',
        });
        final decoded = _parse(json, objectType: 'todo')!;
        expect(decoded.toJson(), equals(json));

        const literalTitle = '  原始标题 · Todo  \n';
        final zh = decoded.render(
          title: literalTitle,
          subtitle: '旧中文副标题',
          kinds: <ReminderKind>{ReminderKind.push, ReminderKind.popup},
          locale: AppLocale.zh,
        );
        final en = decoded.render(
          title: literalTitle,
          subtitle: 'old subtitle',
          kinds: <ReminderKind>{ReminderKind.push, ReminderKind.popup},
          locale: AppLocale.en,
        );
        expect(zh.title, literalTitle);
        expect(zh.subtitle, '待办 · 一次提醒 · 普通通知、弹出提醒 · 2 条规则');
        expect(en.title, literalTitle);
        expect(
          en.subtitle,
          'Todo · One-time reminder · Notification, Popup · 2 rules',
        );

        final defaultGoal = ReminderScheduleDisplayCopy.rules(
          ReminderScheduleSubject.goal,
          defaultTitle: true,
          repeating: true,
          ruleCount: 1,
        );
        final goalJson = defaultGoal.toJson();
        final zhGoal = defaultGoal.render(
          title: '',
          subtitle: '',
          kinds: const <ReminderKind>{},
          locale: AppLocale.zh,
        );
        final enGoal = defaultGoal.render(
          title: '',
          subtitle: '',
          kinds: const <ReminderKind>{},
          locale: AppLocale.en,
        );
        expect(
          _parse(goalJson, objectType: 'goal')!.toJson(),
          equals(goalJson),
        );
        expect(zhGoal.title, '目标提醒');
        expect(zhGoal.subtitle, '目标 · 重复提醒 · 系统提醒 · 1 条规则');
        expect(enGoal.title, 'Goal reminder');
        expect(
          enGoal.subtitle,
          'Goal · Repeating reminder · System reminder · 1 rule',
        );
      },
    );

    test(
      'habit records retain immutable weekdays, local time and primary kind',
      () {
        final sourceWeekdays = <int>[1, 3];
        final copy = ReminderScheduleDisplayCopy.habit(
          defaultTitle: false,
          primaryKind: ReminderKind.push,
          weekdays: sourceWeekdays,
          hour: 7,
          minute: 0,
        );
        sourceWeekdays
          ..[0] = 5
          ..add(7);
        expect(copy.weekdays, <int>[1, 3]);
        expect(() => copy.weekdays.add(5), throwsUnsupportedError);

        final json = copy.toJson();
        expect(json.keys.toSet(), <String>{
          'schemaVersion',
          'shape',
          'subject',
          'titleMode',
          'primaryKind',
          'weekdays',
          'hour',
          'minute',
        });
        expect(json['hour'], 7);
        expect(json['minute'], 0);
        final decoded = _parse(json, objectType: 'habit')!;
        expect(decoded.toJson(), equals(json));
        expect(() => decoded.weekdays.add(5), throwsUnsupportedError);

        const literalTitle = '\t喝水  Habit  ';
        final zh = decoded.render(
          title: literalTitle,
          subtitle: '旧副标题',
          kinds: const <ReminderKind>{ReminderKind.push, ReminderKind.alarm},
          locale: AppLocale.zh,
        );
        final en = decoded.render(
          title: literalTitle,
          subtitle: 'old subtitle',
          kinds: const <ReminderKind>{ReminderKind.push, ReminderKind.alarm},
          locale: AppLocale.en,
        );
        expect(zh.title, literalTitle);
        expect(zh.subtitle, '日常 · 普通通知 · 周一、周三 07:00');
        expect(en.title, literalTitle);
        expect(en.subtitle, 'Habit · Notification · Mon, Wed 07:00');

        final everyDay = ReminderScheduleDisplayCopy.habit(
          defaultTitle: true,
          primaryKind: ReminderKind.alarm,
          weekdays: const <int>[1, 2, 3, 4, 5, 6, 7],
          hour: 8,
          minute: 30,
        );
        expect(
          everyDay
              .render(
                title: '',
                subtitle: '',
                kinds: const <ReminderKind>{},
                locale: AppLocale.zh,
              )
              .title,
          '日常提醒',
        );
        expect(
          everyDay
              .render(
                title: '',
                subtitle: '',
                kinds: const <ReminderKind>{},
                locale: AppLocale.en,
              )
              .title,
          'Habit reminder',
        );
        expect(
          everyDay
              .render(
                title: '',
                subtitle: '',
                kinds: const <ReminderKind>{},
                locale: AppLocale.en,
              )
              .subtitle,
          'Habit · Alarm · Every day 08:30',
        );

        final unsetTime = ReminderScheduleDisplayCopy.habit(
          primaryKind: ReminderKind.popup,
          weekdays: const <int>[],
        );
        expect(unsetTime.toJson()['hour'], isNull);
        expect(unsetTime.toJson()['minute'], isNull);
        expect(
          unsetTime
              .render(
                title: '',
                subtitle: '',
                kinds: const <ReminderKind>{},
                locale: AppLocale.zh,
              )
              .subtitle,
          '日常 · 弹出提醒 · 每天 时间未设置',
        );
        expect(
          unsetTime
              .render(
                title: '',
                subtitle: '',
                kinds: const <ReminderKind>{},
                locale: AppLocale.en,
              )
              .subtitle,
          'Habit · Popup · Every day Time not set',
        );
      },
    );

    test(
      'dated records render captured date and time without recomputing them',
      () {
        final at = DateTime.utc(2028, 2, 29, 7, 5);
        final copy = ReminderScheduleDisplayCopy.dated(
          ReminderScheduleSubject.anniversary,
          defaultTitle: false,
          primaryKind: ReminderKind.alarm,
          at: at,
        );
        final json = copy.toJson();
        expect(json.keys.toSet(), <String>{
          'schemaVersion',
          'shape',
          'subject',
          'titleMode',
          'primaryKind',
          'year',
          'month',
          'day',
          'hour',
          'minute',
        });
        expect(json, containsPair('year', 2028));
        expect(json, containsPair('month', 2));
        expect(json, containsPair('day', 29));
        expect(json, containsPair('hour', 7));
        expect(json, containsPair('minute', 5));

        final decoded = _parse(json, objectType: 'anniversary')!;
        expect(decoded.toJson(), equals(json));
        const literalTitle = '  Anniversary 原文\n';
        final zh = decoded.render(
          title: literalTitle,
          subtitle: '旧副标题',
          kinds: const <ReminderKind>{},
          locale: AppLocale.zh,
        );
        final en = decoded.render(
          title: literalTitle,
          subtitle: 'old subtitle',
          kinds: const <ReminderKind>{},
          locale: AppLocale.en,
        );
        expect(zh.title, literalTitle);
        expect(zh.subtitle, '纪念日 · 闹钟提醒 · 02-29 07:05');
        expect(en.title, literalTitle);
        expect(en.subtitle, 'Anniversary · Alarm · 02-29 07:05');
        expect(decoded.toJson(), equals(json));

        final countdown = ReminderScheduleDisplayCopy.dated(
          ReminderScheduleSubject.countdown,
          defaultTitle: true,
          primaryKind: ReminderKind.email,
          at: DateTime(2027, 1, 2, 0, 5),
        );
        final zhCountdown = countdown.render(
          title: '',
          subtitle: '',
          kinds: const <ReminderKind>{},
          locale: AppLocale.zh,
        );
        final enCountdown = countdown.render(
          title: '',
          subtitle: '',
          kinds: const <ReminderKind>{},
          locale: AppLocale.en,
        );
        expect(zhCountdown.title, '倒数日提醒');
        expect(zhCountdown.subtitle, '倒数日 · 邮件提醒 · 01-02 00:05');
        expect(enCountdown.title, 'Countdown reminder');
        expect(enCountdown.subtitle, 'Countdown · Email · 01-02 00:05');
        expect(
          _parse(countdown.toJson(), objectType: 'countdown')!.toJson(),
          equals(countdown.toJson()),
        );
      },
    );

    test('explicit locale rendering does not change the global locale', () {
      final before = I18n.current;
      final copy = ReminderScheduleDisplayCopy.registered(
        ReminderScheduleSubject.todo,
      );
      copy.render(
        title: '',
        subtitle: '',
        kinds: const <ReminderKind>{},
        locale: AppLocale.en,
      );
      copy.render(
        title: '',
        subtitle: '',
        kinds: const <ReminderKind>{},
        locale: AppLocale.zh,
      );
      expect(I18n.current, before);
    });
  });

  group('ReminderScheduleDisplayCopy strict parser', () {
    test('accepts exact schemas and active primary kinds', () {
      expect(
        _parse(_registeredJson(), objectType: 'todo')!.toJson(),
        _registeredJson(),
      );
      expect(_parse(_rulesJson(), objectType: 'todo')!.toJson(), _rulesJson());
      expect(_parse(_habitJson(), objectType: 'habit')!.toJson(), _habitJson());
      expect(
        _parse(_datedJson(), objectType: 'anniversary')!.toJson(),
        _datedJson(),
      );

      for (final kind in <ReminderKind>[
        ReminderKind.push,
        ReminderKind.popup,
        ReminderKind.alarm,
        ReminderKind.email,
      ]) {
        final habit = _habitJson(primaryKind: kind.name);
        final dated = _datedJson(primaryKind: kind.name);
        expect(_parse(habit, objectType: 'habit')!.toJson(), equals(habit));
        expect(
          _parse(dated, objectType: 'anniversary')!.toJson(),
          equals(dated),
        );
      }

      expect(
        _parse(
          _rulesJson(ruleCount: _maxSafeJsonInteger),
          objectType: 'todo',
        )!.toJson()['ruleCount'],
        _maxSafeJsonInteger,
      );
      expect(
        _parse(
          _habitJson(weekdays: const <int>[]),
          objectType: 'habit',
        )!.weekdays,
        isEmpty,
      );
      expect(
        _parse(
          _habitJson(weekdays: const <int>[1, 2, 3, 4, 5, 6, 7]),
          objectType: 'habit',
        )!.weekdays,
        <int>[1, 2, 3, 4, 5, 6, 7],
      );
      expect(
        _parse(
          _habitJson(hour: null, minute: null),
          objectType: 'habit',
        )!.toJson(),
        _habitJson(hour: null, minute: null),
      );
    });

    test(
      'rejects legacy, unsupported versions, malformed maps and extra keys',
      () {
        _expectNull(null);
        _expectNull('legacy string');
        _expectNull(<Object?>[]);
        _expectNull(_registeredJson(schemaVersion: 2));
        _expectNull(_registeredJson(schemaVersion: '1'));
        _expectNull(_registeredJson(schemaVersion: 1.0));
        _expectNull(_registeredJson(schemaVersion: true));
        _expectNull(_registeredJson(shape: 'unknown'));
        _expectNull(_registeredJson(subject: 'unknown'));
        _expectNull(_registeredJson(titleMode: 'literal'));

        final missingKey = _rulesJson()..remove('ruleCount');
        _expectNull(missingKey);
        final extraKey = _habitJson()..['ignored'] = true;
        _expectNull(extraKey, objectType: 'habit');
        final nonStringKey = <Object?, Object?>{..._datedJson(), 7: 'extra'};
        _expectNull(nonStringKey, objectType: 'anniversary');

        _expectNull(_rulesJson(subject: 'habit'), objectType: 'habit');
        _expectNull(_habitJson(subject: 'todo'));
        _expectNull(_datedJson(subject: 'goal'), objectType: 'goal');
        _expectNull(_registeredJson(), objectType: 'goal');
        _expectNull(_registeredJson(subject: 'countdown'), objectType: 'other');
      },
    );

    test('requires strict rules types and positive safe counts', () {
      for (final value in <bool>[false, true]) {
        expect(_parse(_rulesJson(repeating: value))?.repeating, value);
      }
      for (final value in <Object?>[1, 'false', 0, 1.0, null]) {
        _expectNull(_rulesJson(repeating: value));
      }
      for (final value in <Object?>[
        true,
        '2',
        2.0,
        0,
        -1,
        _maxSafeJsonInteger + 1,
        null,
      ]) {
        _expectNull(_rulesJson(ruleCount: value));
      }
      _expectNull(_rulesJson(titleMode: 'other'));
      _expectNull(_rulesJson(shape: 'registered'));
      _expectNull(_rulesJson(subject: 'anniversary'));
    });

    test('rejects invalid habit kinds, weekday values and time pairs', () {
      for (final value in <Object?>[
        'off',
        'unknown',
        ReminderKind.push,
        null,
        1,
      ]) {
        _expectNull(_habitJson(primaryKind: value), objectType: 'habit');
      }
      for (final value in <Object?>[
        null,
        '1,3',
        <Object?>[1, 2.0],
        <Object?>[1, '3'],
        <Object?>[1, true],
        <int>[0],
        <int>[8],
        <int>[1, 1],
        <int>[1, 2, 3, 4, 5, 6, 7, 1],
      ]) {
        _expectNull(_habitJson(weekdays: value), objectType: 'habit');
      }

      for (final value in <Object?>[true, '7', 7.0, -1, 24]) {
        _expectNull(_habitJson(hour: value), objectType: 'habit');
      }
      for (final value in <Object?>[true, '0', 0.0, -1, 60]) {
        _expectNull(_habitJson(minute: value), objectType: 'habit');
      }
      _expectNull(_habitJson(hour: null, minute: 0), objectType: 'habit');
      _expectNull(_habitJson(hour: 7, minute: null), objectType: 'habit');
      _expectNull(
        _habitJson(titleMode: 'default-but-not-literal'),
        objectType: 'habit',
      );
      _expectNull(_habitJson(subject: 'goal'), objectType: 'goal');
    });

    test(
      'rejects invalid dated kinds, component types and impossible dates',
      () {
        for (final value in <Object?>[
          'off',
          'unknown',
          ReminderKind.alarm,
          null,
          2,
        ]) {
          _expectNull(
            _datedJson(primaryKind: value),
            objectType: 'anniversary',
          );
        }
        for (final field in <String>['year', 'month', 'day']) {
          for (final value in <Object?>[true, '2', 2.0, null]) {
            final json = _datedJson()..[field] = value;
            _expectNull(json, objectType: 'anniversary');
          }
        }
        for (final field in <String>['hour', 'minute']) {
          for (final value in <Object?>[true, '2', 2.0, null]) {
            final json = _datedJson()..[field] = value;
            _expectNull(json, objectType: 'anniversary');
          }
        }

        for (final invalid in <Map<String, Object?>>[
          _datedJson(year: 0),
          _datedJson(year: 10000),
          _datedJson(month: 0),
          _datedJson(month: 13),
          _datedJson(day: 0),
          _datedJson(day: 30),
          _datedJson(year: 2023, month: 2, day: 29),
          _datedJson(year: 2024, month: 4, day: 31),
          _datedJson(hour: -1),
          _datedJson(hour: 24),
          _datedJson(minute: -1),
          _datedJson(minute: 60),
        ]) {
          _expectNull(invalid, objectType: 'anniversary');
        }
        expect(
          _parse(
            _datedJson(year: 2024, month: 2, day: 29),
            objectType: 'anniversary',
          )!.toJson(),
          _datedJson(year: 2024, month: 2, day: 29),
        );
        expect(
          _parse(
            _datedJson(year: 1, month: 1, day: 1, hour: 0, minute: 0),
            objectType: 'anniversary',
          ),
          isNotNull,
        );
        expect(
          _parse(
            _datedJson(year: 9999, month: 12, day: 31, hour: 23, minute: 59),
            objectType: 'anniversary',
          ),
          isNotNull,
        );
        _expectNull(
          _datedJson(titleMode: 'default-but-not-literal'),
          objectType: 'anniversary',
        );
        _expectNull(_datedJson(subject: 'todo'));
      },
    );

    test('rejects wrong JSON types for common fields and exact shape keys', () {
      final registeredCases = <Map<String, Object?>>[
        _registeredJson(shape: 1),
        _registeredJson(subject: true),
        _registeredJson(titleMode: 1),
        _registeredJson()..['extra'] = null,
        _registeredJson()..remove('titleMode'),
      ];
      for (final json in registeredCases) {
        _expectNull(json);
      }

      final rulesCases = <Map<String, Object?>>[
        _rulesJson(shape: null),
        _rulesJson(subject: 1),
        _rulesJson(titleMode: false),
        _rulesJson()..['extra'] = null,
        _rulesJson()..remove('repeating'),
      ];
      for (final json in rulesCases) {
        _expectNull(json);
      }

      final habitCases = <Map<String, Object?>>[
        _habitJson(shape: null),
        _habitJson(subject: 1),
        _habitJson(titleMode: false),
        _habitJson()..['extra'] = null,
        _habitJson()..remove('weekdays'),
      ];
      for (final json in habitCases) {
        _expectNull(json, objectType: 'habit');
      }

      final datedCases = <Map<String, Object?>>[
        _datedJson(shape: null),
        _datedJson(subject: 1),
        _datedJson(titleMode: false),
        _datedJson()..['extra'] = null,
        _datedJson()..remove('year'),
      ];
      for (final json in datedCases) {
        _expectNull(json, objectType: 'anniversary');
      }
    });
  });
}
