import 'dart:convert';

import 'package:duoyi/core/app_brand.dart' show AppBrands, BrandStyle;
import 'package:duoyi/core/brand_strings.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/goal.dart' show ReminderKind, ReminderRuleType;
import 'package:duoyi/services/reminder_delivery_copy.dart';
import 'package:flutter_test/flutter_test.dart';

({String title, String body}) _render(
  ReminderDeliveryCopy copy,
  AppLocale locale, {
  BrandStyle style = BrandStyle.defaultBrand,
}) {
  return copy.render(
    locale: locale,
    strings: BrandStrings.forLocale(style, locale),
  );
}

const _descriptorKeys = <String>[
  'schemaVersion',
  'subject',
  'userTitle',
  'type',
  'kind',
  'days',
  'semanticPush',
];
const _maxExactJsonInteger = 9007199254740991;

typedef _CopyFixture = ({
  ReminderDeliveryCopy copy,
  Map<String, Object?> expectedDescriptor,
  String expectedFingerprint,
  String title,
});

ReminderRuleType _ruleFromFixtureName(String name) => switch (name) {
  'absolute' => ReminderRuleType.absolute,
  'relativeToDue' => ReminderRuleType.relativeToDue,
  'dailyTime' => ReminderRuleType.dailyTime,
  'weeklyTime' => ReminderRuleType.weeklyTime,
  _ => throw StateError('Unknown fixture rule: $name'),
};

ReminderKind _kindFromFixtureName(String name) => switch (name) {
  'push' => ReminderKind.push,
  'alarm' => ReminderKind.alarm,
  'email' => ReminderKind.email,
  'popup' => ReminderKind.popup,
  'off' => ReminderKind.off,
  _ => throw StateError('Unknown fixture kind: $name'),
};

ReminderDeliveryCopy _copyFromFixture({
  required String subject,
  required String title,
  required String type,
  required String kind,
  required int days,
  required bool semanticPush,
}) => switch (subject) {
  'todo' => ReminderDeliveryCopy.todo(title, _ruleFromFixtureName(type)),
  'goal' => ReminderDeliveryCopy.goal(
    title,
    _ruleFromFixtureName(type),
    _kindFromFixtureName(kind),
  ),
  'habit' => ReminderDeliveryCopy.habit(title, semanticPush: semanticPush),
  'anniversary' => ReminderDeliveryCopy.anniversary(
    title,
    days,
    _kindFromFixtureName(kind),
  ),
  'countdown' => ReminderDeliveryCopy.countdown(title, days),
  _ => throw StateError('Unknown fixture subject: $subject'),
};

Map<String, Object?> _expectedDescriptor({
  required String subject,
  required String title,
  required String type,
  required String kind,
  required int days,
  required bool semanticPush,
}) => <String, Object?>{
  'schemaVersion': 1,
  'subject': subject,
  'userTitle': title,
  'type': type,
  'kind': kind,
  'days': days,
  'semanticPush': semanticPush,
};

List<_CopyFixture> _allValidCopyFixtures() {
  const title = '  提醒：🔔\nA/B "literal" \\n e\u0301  ';
  const rules = <String>[
    'absolute',
    'relativeToDue',
    'dailyTime',
    'weeklyTime',
  ];
  const kinds = <String>['push', 'alarm', 'email', 'popup', 'off'];
  final fixtures = <_CopyFixture>[];

  void add({
    required String subject,
    required String type,
    required String kind,
    required int days,
    required bool semanticPush,
  }) {
    final descriptor = _expectedDescriptor(
      subject: subject,
      title: title,
      type: type,
      kind: kind,
      days: days,
      semanticPush: semanticPush,
    );
    fixtures.add((
      copy: _copyFromFixture(
        subject: subject,
        title: title,
        type: type,
        kind: kind,
        days: days,
        semanticPush: semanticPush,
      ),
      expectedDescriptor: descriptor,
      expectedFingerprint: jsonEncode([
        subject,
        title,
        type,
        kind,
        days,
        semanticPush,
      ]),
      title: title,
    ));
  }

  for (final type in rules) {
    add(
      subject: 'todo',
      type: type,
      kind: 'push',
      days: 0,
      semanticPush: false,
    );
  }
  for (final type in rules) {
    for (final kind in kinds) {
      add(
        subject: 'goal',
        type: type,
        kind: kind,
        days: 0,
        semanticPush: false,
      );
    }
  }
  for (final semanticPush in const [false, true]) {
    add(
      subject: 'habit',
      type: 'absolute',
      kind: 'push',
      days: 0,
      semanticPush: semanticPush,
    );
  }
  for (final kind in kinds) {
    add(
      subject: 'anniversary',
      type: 'absolute',
      kind: kind,
      days: -8,
      semanticPush: false,
    );
  }
  add(
    subject: 'countdown',
    type: 'absolute',
    kind: 'push',
    days: 8,
    semanticPush: false,
  );
  return fixtures;
}

void main() {
  setUp(() => I18n.setLocale(AppLocale.zh));
  tearDown(() => I18n.setLocale(AppLocale.zh));

  test('todo copy covers every rule type in Chinese and English', () {
    I18n.setLocale(AppLocale.en);
    const title = '整理书桌';
    final expectedTitles = <AppLocale, Map<ReminderRuleType, String>>{
      AppLocale.zh: <ReminderRuleType, String>{
        ReminderRuleType.absolute: '提醒：$title',
        ReminderRuleType.relativeToDue: '提醒：$title',
        ReminderRuleType.dailyTime: '今日提醒',
        ReminderRuleType.weeklyTime: '今日提醒',
      },
      AppLocale.en: <ReminderRuleType, String>{
        ReminderRuleType.absolute: 'Reminder: $title',
        ReminderRuleType.relativeToDue: 'Reminder: $title',
        ReminderRuleType.dailyTime: "Today's reminders",
        ReminderRuleType.weeklyTime: "Today's reminders",
      },
    };
    expect(
      expectedTitles[AppLocale.zh]!.keys.toSet(),
      ReminderRuleType.values.toSet(),
    );
    expect(
      expectedTitles[AppLocale.en]!.keys.toSet(),
      ReminderRuleType.values.toSet(),
    );

    for (final locale in AppLocale.values) {
      for (final type in ReminderRuleType.values) {
        expect(
          _render(ReminderDeliveryCopy.todo(title, type), locale),
          (title: expectedTitles[locale]![type]!, body: title),
          reason: '$locale / $type',
        );
      }
    }

    expect(I18n.current, AppLocale.en);
    expect(I18n.localeListenable.value, AppLocale.en);
  });

  test('goal copy covers every rule type and reminder kind', () {
    I18n.setLocale(AppLocale.en);
    const title = '完成周报';
    const labels = <AppLocale, Map<ReminderRuleType, String>>{
      AppLocale.zh: <ReminderRuleType, String>{
        ReminderRuleType.absolute: '目标提醒',
        ReminderRuleType.relativeToDue: '目标提前提醒',
        ReminderRuleType.dailyTime: '每日目标提醒',
        ReminderRuleType.weeklyTime: '每周目标提醒',
      },
      AppLocale.en: <ReminderRuleType, String>{
        ReminderRuleType.absolute: 'Goal reminder',
        ReminderRuleType.relativeToDue: 'Upcoming goal reminder',
        ReminderRuleType.dailyTime: 'Daily goal reminder',
        ReminderRuleType.weeklyTime: 'Weekly goal reminder',
      },
    };
    const prefixes = <ReminderKind, String>{
      ReminderKind.push: '🔔',
      ReminderKind.alarm: '⏰',
      ReminderKind.email: '✉️',
      ReminderKind.popup: '🔔',
      ReminderKind.off: '🔕',
    };
    expect(labels[AppLocale.zh]!.keys.toSet(), ReminderRuleType.values.toSet());
    expect(labels[AppLocale.en]!.keys.toSet(), ReminderRuleType.values.toSet());
    expect(prefixes.keys.toSet(), ReminderKind.values.toSet());

    for (final locale in AppLocale.values) {
      for (final type in ReminderRuleType.values) {
        for (final kind in ReminderKind.values) {
          expect(
            _render(ReminderDeliveryCopy.goal(title, type, kind), locale),
            (title: '${prefixes[kind]} ${labels[locale]![type]}', body: title),
            reason: '$locale / $type / $kind',
          );
        }
      }
    }

    expect(I18n.current, AppLocale.en);
    expect(I18n.localeListenable.value, AppLocale.en);
  });

  test(
    'habit copy keeps semantic push distinct and uses each brand locale',
    () {
      I18n.setLocale(AppLocale.en);
      final brandCases = <(BrandStyle, String, String, String, String)>[
        (
          AppBrands.defaultBrand.style,
          '今日提醒',
          "Today's reminders",
          '习惯打卡提醒',
          'Habit check-in reminder',
        ),
        (
          AppBrands.re0.style,
          '咒文即将失效',
          'A Spell Nears Its Expiry',
          '契约提醒',
          'Pact Reminder',
        ),
        (
          AppBrands.liquidGlass.style,
          '待办提醒',
          'Task reminder',
          '习惯打卡提醒',
          'Habit reminder',
        ),
      ];

      for (final (style, zhTodoTitle, enTodoTitle, zhHabitTitle, enHabitTitle)
          in brandCases) {
        final zhGeneric = _render(
          const ReminderDeliveryCopy.habit('读书'),
          AppLocale.zh,
          style: style,
        );
        final enGeneric = _render(
          const ReminderDeliveryCopy.habit('读书'),
          AppLocale.en,
          style: style,
        );
        final zhSemantic = _render(
          const ReminderDeliveryCopy.habit('读书', semanticPush: true),
          AppLocale.zh,
          style: style,
        );
        final enSemantic = _render(
          const ReminderDeliveryCopy.habit('读书', semanticPush: true),
          AppLocale.en,
          style: style,
        );

        expect(zhGeneric.title, zhHabitTitle);
        expect(enGeneric.title, enHabitTitle);
        expect(zhSemantic.title, zhHabitTitle);
        expect(enSemantic.title, enHabitTitle);
        expect(zhGeneric.body, '读书 到时间了，点开确认打卡');
        expect(enGeneric.body, 'Time for 读书. Open to check in.');
        expect(zhSemantic.body, '别忘了: 读书');
        expect(enSemantic.body, "Don't forget: 读书");

        final zhTodo = _render(
          const ReminderDeliveryCopy.todo('读书', ReminderRuleType.dailyTime),
          AppLocale.zh,
          style: style,
        );
        final enTodo = _render(
          const ReminderDeliveryCopy.todo('读书', ReminderRuleType.dailyTime),
          AppLocale.en,
          style: style,
        );
        expect(zhTodo.title, zhTodoTitle);
        expect(enTodo.title, enTodoTitle);
      }

      expect(I18n.current, AppLocale.en);
      expect(I18n.localeListenable.value, AppLocale.en);
    },
  );

  test('anniversary copy covers every kind and calendar distance fact', () {
    I18n.setLocale(AppLocale.en);
    const title = '奶奶生日';
    const prefixes = <ReminderKind, String>{
      ReminderKind.push: '📅',
      ReminderKind.alarm: '⏰',
      ReminderKind.email: '📅',
      ReminderKind.popup: '🔔',
      ReminderKind.off: '📅',
    };
    const distances = <AppLocale, Map<int, String>>{
      AppLocale.zh: <int, String>{
        0: '今天是 奶奶生日',
        1: '1 天后是 奶奶生日',
        8: '8 天后是 奶奶生日',
      },
      AppLocale.en: <int, String>{
        0: 'Today is 奶奶生日',
        1: '奶奶生日 is in 1 day.',
        8: '奶奶生日 is in 8 days.',
      },
    };
    expect(prefixes.keys.toSet(), ReminderKind.values.toSet());

    for (final locale in AppLocale.values) {
      expect(distances[locale]!.keys.toSet(), <int>{0, 1, 8});
      for (final kind in ReminderKind.values) {
        for (final days in distances[locale]!.keys) {
          expect(
            _render(
              ReminderDeliveryCopy.anniversary(title, days, kind),
              locale,
            ),
            (
              title:
                  '${prefixes[kind]} ${locale == AppLocale.zh ? '纪念日提醒' : 'Anniversary reminder'}',
              body: distances[locale]![days]!,
            ),
            reason: '$locale / $kind / $days days',
          );
        }
      }
    }

    expect(I18n.current, AppLocale.en);
    expect(I18n.localeListenable.value, AppLocale.en);
  });

  test('countdown copy covers today, tomorrow, later, and overdue facts', () {
    I18n.setLocale(AppLocale.en);
    const title = '旅行';
    const distances = <AppLocale, Map<int, String>>{
      AppLocale.zh: <int, String>{
        0: '还有 0 天',
        1: '还有 1 天',
        12: '还有 12 天',
        -1: '已过 1 天',
        -6: '已过 6 天',
      },
      AppLocale.en: <int, String>{
        0: '0 days to go',
        1: '1 day to go',
        12: '12 days to go',
        -1: '1 day ago',
        -6: '6 days ago',
      },
    };
    const expectedDays = <int>{0, 1, 12, -1, -6};

    for (final locale in AppLocale.values) {
      expect(distances[locale]!.keys.toSet(), expectedDays);
      for (final days in expectedDays) {
        expect(
          _render(ReminderDeliveryCopy.countdown(title, days), locale),
          (
            title: locale == AppLocale.zh
                ? '🔔 倒数日提醒'
                : '🔔 Countdown reminder',
            body: '$title · ${distances[locale]![days]}',
          ),
          reason: '$locale / $days days',
        );
      }
    }

    expect(I18n.current, AppLocale.en);
    expect(I18n.localeListenable.value, AppLocale.en);
  });

  test('raw user titles survive every subject renderer unchanged', () {
    I18n.setLocale(AppLocale.en);
    const rawTitles = <String>[
      '提醒：🔔 倒数日提醒\n🔔 Countdown reminder\n中文任务 🧭\n',
      'Today is ⏰ Goal reminder\n目标提醒：✉️\n  保留空格  ',
    ];

    for (final raw in rawTitles) {
      final copies = <ReminderDeliveryCopy>[
        ReminderDeliveryCopy.todo(raw, ReminderRuleType.absolute),
        ReminderDeliveryCopy.todo(raw, ReminderRuleType.weeklyTime),
        ReminderDeliveryCopy.goal(
          raw,
          ReminderRuleType.absolute,
          ReminderKind.push,
        ),
        ReminderDeliveryCopy.habit(raw),
        ReminderDeliveryCopy.habit(raw, semanticPush: true),
        ReminderDeliveryCopy.anniversary(raw, 3, ReminderKind.popup),
        ReminderDeliveryCopy.countdown(raw, -2),
      ];

      for (final locale in AppLocale.values) {
        for (final (index, copy) in copies.indexed) {
          final rendered = _render(copy, locale);
          expect(copy.userTitle, raw, reason: '$locale / domain index $index');
          expect(
            rendered.title.contains(raw) || rendered.body.contains(raw),
            isTrue,
            reason: '$locale / domain index $index',
          );
          if (index < 3) {
            expect(rendered.body, raw, reason: '$locale / domain index $index');
          } else {
            expect(
              rendered.body.contains(raw),
              isTrue,
              reason: '$locale / domain index $index',
            );
          }
        }
      }
    }

    expect(I18n.current, AppLocale.en);
    expect(I18n.localeListenable.value, AppLocale.en);
  });

  test(
    'the same copy renders zh to en to zh without changing global locale',
    () {
      I18n.setLocale(AppLocale.en);
      const copy = ReminderDeliveryCopy.countdown('考试日 🔔\n考试提醒', 1);

      final firstChinese = _render(copy, AppLocale.zh);
      final english = _render(copy, AppLocale.en);
      final secondChinese = _render(copy, AppLocale.zh);

      expect(firstChinese, secondChinese);
      expect(firstChinese.title, '🔔 倒数日提醒');
      expect(firstChinese.body, '考试日 🔔\n考试提醒 · 还有 1 天');
      expect(english.title, '🔔 Countdown reminder');
      expect(english.body, '考试日 🔔\n考试提醒 · 1 day to go');
      expect(I18n.current, AppLocale.en);
      expect(I18n.localeListenable.value, AppLocale.en);
    },
  );

  test('semantic fingerprint is stable across locale and brand rendering', () {
    I18n.setLocale(AppLocale.en);
    const copy = ReminderDeliveryCopy.habit('晚间散步', semanticPush: true);
    final originalFingerprint = copy.semanticFingerprint;

    final firstChinese = _render(
      copy,
      AppLocale.zh,
      style: AppBrands.defaultBrand.style,
    );
    expect(copy.semanticFingerprint, originalFingerprint);
    final englishRe0 = _render(copy, AppLocale.en, style: AppBrands.re0.style);
    expect(copy.semanticFingerprint, originalFingerprint);
    final secondChinese = _render(
      copy,
      AppLocale.zh,
      style: AppBrands.defaultBrand.style,
    );
    expect(copy.semanticFingerprint, originalFingerprint);

    expect(firstChinese, secondChinese);
    expect(firstChinese.title, '习惯打卡提醒');
    expect(firstChinese.body, '别忘了: 晚间散步');
    expect(englishRe0.title, 'Pact Reminder');
    expect(englishRe0.body, "Don't forget: 晚间散步");

    final englishDefault = _render(
      copy,
      AppLocale.en,
      style: AppBrands.defaultBrand.style,
    );
    final englishGlass = _render(
      copy,
      AppLocale.en,
      style: AppBrands.liquidGlass.style,
    );
    expect(englishDefault.title, 'Habit check-in reminder');
    expect(englishGlass.title, 'Habit reminder');
    expect(copy.semanticFingerprint, originalFingerprint);
    expect(I18n.current, AppLocale.en);
    expect(I18n.localeListenable.value, AppLocale.en);
  });

  test('semantic fingerprint changes when any semantic fact changes', () {
    const todo = ReminderDeliveryCopy.todo('同一标题', ReminderRuleType.absolute);
    const goal = ReminderDeliveryCopy.goal(
      '同一标题',
      ReminderRuleType.absolute,
      ReminderKind.push,
    );
    const anotherType = ReminderDeliveryCopy.todo(
      '同一标题',
      ReminderRuleType.dailyTime,
    );
    const anotherKind = ReminderDeliveryCopy.goal(
      '同一标题',
      ReminderRuleType.absolute,
      ReminderKind.alarm,
    );
    const countdownToday = ReminderDeliveryCopy.countdown('同一标题', 0);
    const countdownTomorrow = ReminderDeliveryCopy.countdown('同一标题', 1);
    const genericHabit = ReminderDeliveryCopy.habit('同一标题');
    const semanticHabit = ReminderDeliveryCopy.habit(
      '同一标题',
      semanticPush: true,
    );
    const anotherTitle = ReminderDeliveryCopy.todo(
      '不同标题',
      ReminderRuleType.absolute,
    );

    expect(goal.semanticFingerprint, isNot(todo.semanticFingerprint));
    expect(anotherType.semanticFingerprint, isNot(todo.semanticFingerprint));
    expect(anotherKind.semanticFingerprint, isNot(goal.semanticFingerprint));
    expect(
      countdownTomorrow.semanticFingerprint,
      isNot(countdownToday.semanticFingerprint),
    );
    expect(
      semanticHabit.semanticFingerprint,
      isNot(genericHabit.semanticFingerprint),
    );
    expect(anotherTitle.semanticFingerprint, isNot(todo.semanticFingerprint));
  });

  test('semantic fingerprint JSON preserves separator and newline titles', () {
    const rawTitle = '用户|第一行\n第二行|absolute|push|0|false';
    const newlineCopy = ReminderDeliveryCopy.todo(
      rawTitle,
      ReminderRuleType.absolute,
    );
    final sameFacts = ReminderDeliveryCopy.todo(
      String.fromCharCodes(rawTitle.codeUnits),
      ReminderRuleType.absolute,
    );
    const literalBackslashTitle = '用户|第一行\\n第二行|absolute|push|0|false';
    const literalBackslashCopy = ReminderDeliveryCopy.todo(
      literalBackslashTitle,
      ReminderRuleType.absolute,
    );
    final nearbyFacts = <ReminderDeliveryCopy>[
      newlineCopy,
      literalBackslashCopy,
      const ReminderDeliveryCopy.todo(
        '用户|第一行\n第二行|absolute|push|0',
        ReminderRuleType.absolute,
      ),
      const ReminderDeliveryCopy.todo(
        '用户|第一行\n第二行|absolute|push|0|false',
        ReminderRuleType.relativeToDue,
      ),
    ];

    expect(newlineCopy.semanticFingerprint, sameFacts.semanticFingerprint);
    expect(
      newlineCopy.semanticFingerprint,
      '["todo","用户|第一行\\n第二行|absolute|push|0|false","absolute","push",0,false]',
    );
    expect(jsonDecode(newlineCopy.semanticFingerprint), <Object?>[
      'todo',
      rawTitle,
      'absolute',
      'push',
      0,
      false,
    ]);
    expect(
      newlineCopy.semanticFingerprint,
      isNot(literalBackslashCopy.semanticFingerprint),
    );
    expect(
      nearbyFacts.map((copy) => copy.semanticFingerprint).toSet(),
      hasLength(nearbyFacts.length),
    );
  });

  test(
    'v1 descriptors have the exact schema and round-trip every valid subject combination',
    () {
      I18n.setLocale(AppLocale.en);
      final fixtures = _allValidCopyFixtures();
      expect(fixtures, hasLength(32));

      for (final fixture in fixtures) {
        final firstMap = fixture.copy.toJson();
        final secondMap = fixture.copy.toJson();
        expect(firstMap.keys.toList(), _descriptorKeys);
        expect(firstMap, fixture.expectedDescriptor);
        expect(identical(firstMap, secondMap), isFalse);

        // Mutating one serialization cannot change the copy or a later map.
        firstMap['userTitle'] = 'changed output only';
        expect(secondMap, fixture.expectedDescriptor);
        expect(fixture.copy.toJson(), fixture.expectedDescriptor);

        final decoded = jsonDecode(jsonEncode(fixture.expectedDescriptor));
        final restored = ReminderDeliveryCopy.tryFromJson(decoded);
        expect(restored, isNotNull);
        final roundTripped = restored!;
        expect(roundTripped.toJson().keys.toList(), _descriptorKeys);
        expect(roundTripped.toJson(), fixture.expectedDescriptor);
        expect(fixture.copy.userTitle.codeUnits, fixture.title.codeUnits);
        expect(roundTripped.userTitle.codeUnits, fixture.title.codeUnits);

        expect(fixture.copy.semanticFingerprint, fixture.expectedFingerprint);
        expect(roundTripped.semanticFingerprint, fixture.expectedFingerprint);
        for (final locale in const [AppLocale.zh, AppLocale.en]) {
          for (final style in const [
            BrandStyle.defaultBrand,
            BrandStyle.re0,
            BrandStyle.liquidGlass,
          ]) {
            expect(
              _render(roundTripped, locale, style: style),
              _render(fixture.copy, locale, style: style),
              reason: '${fixture.expectedDescriptor} / $locale / $style',
            );
          }
        }
      }

      expect(I18n.current, AppLocale.en);
      expect(I18n.localeListenable.value, AppLocale.en);
    },
  );

  test(
    'JSON round-trip preserves raw literal code units, renders, and fingerprint',
    () {
      I18n.setLocale(AppLocale.en);
      const rawTitles = <String>[
        '',
        '      ',
        '  leading and trailing  ',
        'first\r\nsecond\rthird\nfourth',
        r'literal backslash+n: \n',
        'Today is 🔔 Countdown reminder\n目标提醒: ✉️',
        'quote: "double" and \'single\'',
        'family 👨‍👩‍👧‍👦 and compass 🧭',
        'é',
        'e\u0301',
      ];

      for (final raw in rawTitles) {
        final copy = ReminderDeliveryCopy.todo(raw, ReminderRuleType.absolute);
        final expected = _expectedDescriptor(
          subject: 'todo',
          title: raw,
          type: 'absolute',
          kind: 'push',
          days: 0,
          semanticPush: false,
        );
        final expectedFingerprint = jsonEncode([
          'todo',
          raw,
          'absolute',
          'push',
          0,
          false,
        ]);
        final restored = ReminderDeliveryCopy.tryFromJson(
          jsonDecode(jsonEncode(expected)),
        );
        expect(restored, isNotNull);
        final roundTripped = restored!;
        expect(copy.toJson(), expected);
        expect(roundTripped.toJson(), expected);
        expect(copy.userTitle.codeUnits, raw.codeUnits);
        expect(roundTripped.userTitle.codeUnits, raw.codeUnits);
        expect(copy.semanticFingerprint, expectedFingerprint);
        expect(roundTripped.semanticFingerprint, expectedFingerprint);

        for (final locale in const [AppLocale.zh, AppLocale.en]) {
          for (final style in const [
            BrandStyle.defaultBrand,
            BrandStyle.re0,
            BrandStyle.liquidGlass,
          ]) {
            final before = _render(copy, locale, style: style);
            final after = _render(roundTripped, locale, style: style);
            expect(
              after,
              before,
              reason: '$locale / $style / ${raw.codeUnits}',
            );
            expect(before.body.codeUnits, raw.codeUnits);
          }
        }
      }

      expect(I18n.current, AppLocale.en);
      expect(I18n.localeListenable.value, AppLocale.en);
    },
  );

  test('anniversary and countdown keep signed exact integer boundaries', () {
    I18n.setLocale(AppLocale.en);
    const boundaryValues = <int>[
      -_maxExactJsonInteger,
      -8,
      -1,
      0,
      1,
      8,
      _maxExactJsonInteger,
    ];
    const kinds = <String>['push', 'alarm', 'email', 'popup', 'off'];

    for (final days in boundaryValues) {
      for (final kind in kinds) {
        final expected = _expectedDescriptor(
          subject: 'anniversary',
          title: '纪念日',
          type: 'absolute',
          kind: kind,
          days: days,
          semanticPush: false,
        );
        final copy = ReminderDeliveryCopy.anniversary(
          '纪念日',
          days,
          _kindFromFixtureName(kind),
        );
        final restored = ReminderDeliveryCopy.tryFromJson(
          jsonDecode(jsonEncode(expected)),
        );
        expect(copy.toJson(), expected);
        expect(restored, isNotNull);
        expect(restored!.toJson(), expected);
      }

      final countdownExpected = _expectedDescriptor(
        subject: 'countdown',
        title: '倒数日',
        type: 'absolute',
        kind: 'push',
        days: days,
        semanticPush: false,
      );
      final countdown = ReminderDeliveryCopy.countdown('倒数日', days);
      final countdownRestored = ReminderDeliveryCopy.tryFromJson(
        jsonDecode(jsonEncode(countdownExpected)),
      );
      expect(countdown.toJson(), countdownExpected);
      expect(countdownRestored, isNotNull);
      expect(countdownRestored!.toJson(), countdownExpected);
    }

    final outsideValues = <({String subject, String kind, int days})>[
      (subject: 'anniversary', kind: 'push', days: _maxExactJsonInteger + 1),
      (subject: 'anniversary', kind: 'off', days: -_maxExactJsonInteger - 1),
      (subject: 'countdown', kind: 'push', days: _maxExactJsonInteger + 1),
      (subject: 'countdown', kind: 'push', days: -_maxExactJsonInteger - 1),
    ];
    for (final value in outsideValues) {
      final copy = value.subject == 'anniversary'
          ? ReminderDeliveryCopy.anniversary(
              '越界',
              value.days,
              _kindFromFixtureName(value.kind),
            )
          : ReminderDeliveryCopy.countdown('越界', value.days);
      expect(() => copy.toJson(), throwsA(isA<RangeError>()));
      final outsideDescriptor = _expectedDescriptor(
        subject: value.subject,
        title: '越界',
        type: 'absolute',
        kind: value.kind,
        days: value.days,
        semanticPush: false,
      );
      expect(ReminderDeliveryCopy.tryFromJson(outsideDescriptor), isNull);
    }

    expect(I18n.current, AppLocale.en);
    expect(I18n.localeListenable.value, AppLocale.en);
  });

  test('ordinary invalid maps are rejected without casts or enum exceptions', () {
    final valid = _expectedDescriptor(
      subject: 'goal',
      title: '严格解析',
      type: 'absolute',
      kind: 'alarm',
      days: 0,
      semanticPush: false,
    );

    for (final field in _descriptorKeys) {
      final missing = Map<String, Object?>.of(valid)..remove(field);
      expect(
        ReminderDeliveryCopy.tryFromJson(missing),
        isNull,
        reason: 'missing $field',
      );

      final nullValue = Map<String, Object?>.of(valid)..[field] = null;
      expect(
        ReminderDeliveryCopy.tryFromJson(nullValue),
        isNull,
        reason: 'null $field',
      );
    }

    const wrongTypes = <String, Object?>{
      'schemaVersion': 1.0,
      'subject': 3,
      'userTitle': 3,
      'type': false,
      'kind': 3,
      'days': 0.0,
      'semanticPush': 1,
    };
    for (final entry in wrongTypes.entries) {
      final wrong = Map<String, Object?>.of(valid)..[entry.key] = entry.value;
      expect(
        ReminderDeliveryCopy.tryFromJson(wrong),
        isNull,
        reason: 'wrong type for ${entry.key}',
      );
    }

    for (final version in <Object?>[0, 2, -1, '1', true]) {
      final unknown = Map<String, Object?>.of(valid)
        ..['schemaVersion'] = version;
      expect(ReminderDeliveryCopy.tryFromJson(unknown), isNull);
    }
    for (final subject in <String>['Todo', 'todo ', '0', 'task']) {
      final unknown = Map<String, Object?>.of(valid)..['subject'] = subject;
      expect(ReminderDeliveryCopy.tryFromJson(unknown), isNull);
    }
    for (final type in <String>['Absolute', 'absolute ', '0', 'daily']) {
      final unknown = Map<String, Object?>.of(valid)..['type'] = type;
      expect(ReminderDeliveryCopy.tryFromJson(unknown), isNull);
    }
    for (final kind in <String>['PUSH', ' push', '0', 'notification']) {
      final unknown = Map<String, Object?>.of(valid)..['kind'] = kind;
      expect(ReminderDeliveryCopy.tryFromJson(unknown), isNull);
    }
    for (final days in <Object?>['0', 0.0, false]) {
      final wrong = Map<String, Object?>.of(valid)..['days'] = days;
      expect(ReminderDeliveryCopy.tryFromJson(wrong), isNull);
    }
    for (final semanticPush in <Object?>['false', 0, 1]) {
      final wrong = Map<String, Object?>.of(valid)
        ..['semanticPush'] = semanticPush;
      expect(ReminderDeliveryCopy.tryFromJson(wrong), isNull);
    }

    final withExtraKey = Map<String, Object?>.of(valid)
      ..['futureField'] = 'unrecognized';
    expect(ReminderDeliveryCopy.tryFromJson(withExtraKey), isNull);
    final withNonStringKey = <Object?, Object?>{...valid, 7: 'extra'};
    expect(ReminderDeliveryCopy.tryFromJson(withNonStringKey), isNull);

    final malformedInputs = <Object?>[
      null,
      1,
      'not a descriptor',
      ' ["goal", "严格解析", "absolute", "alarm", 0, false] ',
      <Object?>['goal', '严格解析', 'absolute', 'alarm', 0, false],
      <Object?>[],
      Object(),
    ];
    for (final input in malformedInputs) {
      expect(
        ReminderDeliveryCopy.tryFromJson(input),
        isNull,
        reason: 'input $input',
      );
    }

    // Field order is irrelevant to parsing, but fingerprint inputs are not v1 maps.
    final reordered = <String, Object?>{
      'semanticPush': false,
      'days': 0,
      'kind': 'alarm',
      'type': 'absolute',
      'userTitle': '严格解析',
      'subject': 'goal',
      'schemaVersion': 1,
    };
    expect(ReminderDeliveryCopy.tryFromJson(reordered)?.toJson(), valid);
    const fingerprintCopy = ReminderDeliveryCopy.goal(
      '严格解析',
      ReminderRuleType.absolute,
      ReminderKind.alarm,
    );
    expect(
      ReminderDeliveryCopy.tryFromJson(fingerprintCopy.semanticFingerprint),
      isNull,
    );
    expect(
      ReminderDeliveryCopy.tryFromJson(
        jsonDecode(fingerprintCopy.semanticFingerprint),
      ),
      isNull,
    );
  });

  test('subject-specific fixed fields must satisfy the v1 invariants', () {
    final invalidDescriptors = <Map<String, Object?>>[
      _expectedDescriptor(
        subject: 'todo',
        title: 'todo',
        type: 'absolute',
        kind: 'alarm',
        days: 0,
        semanticPush: false,
      ),
      _expectedDescriptor(
        subject: 'todo',
        title: 'todo',
        type: 'absolute',
        kind: 'push',
        days: 1,
        semanticPush: false,
      ),
      _expectedDescriptor(
        subject: 'todo',
        title: 'todo',
        type: 'absolute',
        kind: 'push',
        days: 0,
        semanticPush: true,
      ),
      _expectedDescriptor(
        subject: 'goal',
        title: 'goal',
        type: 'absolute',
        kind: 'push',
        days: 1,
        semanticPush: false,
      ),
      _expectedDescriptor(
        subject: 'goal',
        title: 'goal',
        type: 'absolute',
        kind: 'alarm',
        days: 0,
        semanticPush: true,
      ),
      _expectedDescriptor(
        subject: 'habit',
        title: 'habit',
        type: 'dailyTime',
        kind: 'push',
        days: 0,
        semanticPush: false,
      ),
      _expectedDescriptor(
        subject: 'habit',
        title: 'habit',
        type: 'absolute',
        kind: 'alarm',
        days: 0,
        semanticPush: true,
      ),
      _expectedDescriptor(
        subject: 'habit',
        title: 'habit',
        type: 'absolute',
        kind: 'push',
        days: 1,
        semanticPush: false,
      ),
      _expectedDescriptor(
        subject: 'anniversary',
        title: 'anniversary',
        type: 'relativeToDue',
        kind: 'email',
        days: -1,
        semanticPush: false,
      ),
      _expectedDescriptor(
        subject: 'anniversary',
        title: 'anniversary',
        type: 'absolute',
        kind: 'email',
        days: -1,
        semanticPush: true,
      ),
      _expectedDescriptor(
        subject: 'countdown',
        title: 'countdown',
        type: 'dailyTime',
        kind: 'push',
        days: 1,
        semanticPush: false,
      ),
      _expectedDescriptor(
        subject: 'countdown',
        title: 'countdown',
        type: 'absolute',
        kind: 'popup',
        days: 1,
        semanticPush: false,
      ),
      _expectedDescriptor(
        subject: 'countdown',
        title: 'countdown',
        type: 'absolute',
        kind: 'push',
        days: 1,
        semanticPush: true,
      ),
    ];

    for (final descriptor in invalidDescriptors) {
      expect(
        ReminderDeliveryCopy.tryFromJson(descriptor),
        isNull,
        reason: '$descriptor',
      );
    }
  });

  test('serialization leaves the global locale notifier untouched', () {
    I18n.setLocale(AppLocale.en);
    var notifications = 0;
    void onLocaleChanged() => notifications++;

    I18n.localeListenable.addListener(onLocaleChanged);
    try {
      for (final fixture in _allValidCopyFixtures()) {
        final encoded = fixture.copy.toJson();
        expect(ReminderDeliveryCopy.tryFromJson(encoded), isNotNull);
        expect(I18n.current, AppLocale.en);
        expect(I18n.localeListenable.value, AppLocale.en);
        expect(notifications, 0);
      }
    } finally {
      I18n.localeListenable.removeListener(onLocaleChanged);
    }
    expect(I18n.current, AppLocale.en);
    expect(I18n.localeListenable.value, AppLocale.en);
    expect(notifications, 0);
  });
}
