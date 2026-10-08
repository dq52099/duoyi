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
}
