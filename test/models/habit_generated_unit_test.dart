import 'dart:convert';

import 'package:duoyi/core/habit_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/habit.dart';
import 'package:duoyi/services/backup_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _date = DateTime(2026, 10, 15);
const _dateKey = '2026-10-15';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppLocale savedLocale;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    savedLocale = I18n.current;
    I18n.setLocale(AppLocale.zh);
  });

  tearDown(() => I18n.setLocale(savedLocale));

  test('default generated unit retains the complete legacy Habit payload', () {
    final habit = Habit(
      id: 'legacy-habit',
      name: 'Legacy habit',
      createdAt: _date,
      updatedAt: _date,
    );

    expect(habit.generatedUnitKey, isNull);
    final legacyPayload = <String, dynamic>{
      'id': 'legacy-habit',
      'name': 'Legacy habit',
      'icon': 'track_changes_outlined',
      'colorValue': 0xFF4CAF50,
      'kind': 0,
      'activeWeekdays': <int>[0, 1, 2, 3, 4, 5, 6],
      'targetCount': 1,
      'unit': null,
      'currentStreak': 0,
      'bestStreak': 0,
      'completions': <String, int>{},
      'completionUpdatedAt': <String, String>{},
      'category': null,
      'tags': <String>[],
      'weeklyTarget': 7,
      'flexTarget': null,
      'flexPeriod': null,
      'startDate': null,
      'endDate': null,
      'sortOrder': 0,
      'remind': false,
      'remindHour': null,
      'remindMinute': null,
      'reminderPlan': <String, dynamic>{'enabled': false, 'rules': <dynamic>[]},
      'createdAt': '2026-10-15T00:00:00.000',
      'updatedAt': '2026-10-15T00:00:00.000',
    };
    expect(habit.toJson(), legacyPayload);
    expect(habit.toJson(), isNot(contains('generatedUnitKey')));

    final restored = Habit.fromJson(legacyPayload);
    expect(restored.generatedUnitKey, isNull);
    expect(restored.toJson(), legacyPayload);
  });

  test('generated cup labels pluralize count and target independently', () {
    final cases = <({int count, int target, String zh, String en})>[
      (count: 0, target: 1, zh: '0 杯 / 1 杯', en: '0 cups / 1 cup'),
      (count: 1, target: 2, zh: '1 杯 / 2 杯', en: '1 cup / 2 cups'),
      (count: 2, target: 1, zh: '2 杯 / 1 杯', en: '2 cups / 1 cup'),
    ];

    for (final sample in cases) {
      final habit = _habit(
        id: 'cup-${sample.count}-${sample.target}',
        count: sample.count,
        target: sample.target,
        generatedUnitKey: 'cup',
      );
      expect(habit.formatCountForDate(_date), sample.zh);
      expect(habit.formatCountForDate(_date, locale: AppLocale.en), sample.en);
      expect(
        HabitUiCopy(AppLocale.en).countLabel(
          count: sample.count,
          target: sample.target,
          negative: false,
          generatedUnitKey: 'cup',
        ),
        sample.en,
      );
    }
  });

  test('null generated keys retain default localized count units', () {
    final cases = <({int count, int target, String zh, String en})>[
      (count: 0, target: 1, zh: '0 次 / 1 次', en: '0 times / 1 time'),
      (count: 1, target: 2, zh: '1 次 / 2 次', en: '1 time / 2 times'),
      (count: 2, target: 1, zh: '2 次 / 1 次', en: '2 times / 1 time'),
    ];

    for (final sample in cases) {
      final habit = _habit(
        id: 'default-${sample.count}-${sample.target}',
        count: sample.count,
        target: sample.target,
      );
      expect(habit.generatedUnitKey, isNull);
      expect(habit.formatCountForDate(_date), sample.zh);
      expect(habit.formatCountForDate(_date, locale: AppLocale.en), sample.en);
    }
  });

  test(
    'negative habit generated count units use singular and plural forms',
    () {
      final cases = <({int count, String zh, String en})>[
        (count: 0, zh: '已记录 0 杯', en: 'Recorded 0 cups'),
        (count: 1, zh: '已记录 1 杯', en: 'Recorded 1 cup'),
        (count: 2, zh: '已记录 2 杯', en: 'Recorded 2 cups'),
      ];

      for (final sample in cases) {
        final habit = _habit(
          id: 'negative-cup-${sample.count}',
          count: sample.count,
          target: 1,
          generatedUnitKey: 'cup',
          kind: HabitKind.negative,
        );
        expect(habit.formatCountForDate(_date), sample.zh);
        expect(
          habit.formatCountForDate(_date, locale: AppLocale.en),
          sample.en,
        );
      }
    },
  );

  test(
    'unknown generated unit keys round trip and display default count units',
    () {
      final habit = _habit(
        id: 'unknown-generated-unit',
        count: 2,
        target: 1,
        generatedUnitKey: 'unknown-unit-key',
      );

      expect(habit.formatCountForDate(_date), '2 次 / 1 次');
      expect(
        habit.formatCountForDate(_date, locale: AppLocale.en),
        '2 times / 1 time',
      );
      final encoded = habit.toJson();
      expect(encoded['generatedUnitKey'], 'unknown-unit-key');
      final restored = Habit.fromJson(Map<String, dynamic>.from(encoded));
      expect(restored.generatedUnitKey, 'unknown-unit-key');
      expect(restored.toJson(), encoded);
      expect(restored.formatCountForDate(_date), '2 次 / 1 次');
    },
  );

  test('fromJson preserves generated key strings exactly', () {
    for (final key in <String>['cup', '', '  private-key  ']) {
      final raw = <String, dynamic>{
        ..._habit(id: 'raw-key-${key.hashCode}', count: 1, target: 1).toJson(),
        'generatedUnitKey': key,
      };

      final restored = Habit.fromJson(raw);
      expect(restored.generatedUnitKey, key);
      expect(restored.toJson()['generatedUnitKey'], key);
    }
  });

  test('a literal unit always wins over generated unit provenance', () {
    for (final literal in <String>['', '  ', '次', 'times', 'cup']) {
      final habit = _habit(
        id: 'literal-${literal.hashCode}',
        count: 2,
        target: 1,
        unit: literal,
        generatedUnitKey: 'cup',
      );
      final expected = '2 $literal / 1 $literal';

      expect(habit.formatCountForDate(_date), expected);
      expect(habit.formatCountForDate(_date, locale: AppLocale.en), expected);
      expect(habit.toJson()['unit'], literal);
      expect(habit.toJson()['generatedUnitKey'], 'cup');
    }
  });

  test(
    'weekly and monthly progress keeps generated cup counts and period totals',
    () {
      final weekly = _habit(
        id: 'weekly-cup',
        count: 2,
        target: 1,
        generatedUnitKey: 'cup',
        flexTarget: 5,
        flexPeriod: HabitFlexPeriod.week,
        completions: {'2026-10-13': 4, _dateKey: 2},
      );
      final monthly = _habit(
        id: 'monthly-cup',
        count: 2,
        target: 1,
        generatedUnitKey: 'cup',
        flexTarget: 4,
        flexPeriod: HabitFlexPeriod.month,
        completions: {'2026-10-11': 1, _dateKey: 2},
      );

      expect(weekly.formatCountForDate(_date), '2 杯 · 本周 2/5');
      expect(
        weekly.formatCountForDate(_date, locale: AppLocale.en),
        '2 cups · This week 2/5',
      );
      expect(monthly.formatCountForDate(_date), '2 杯 · 本月 2/4');
      expect(
        monthly.formatCountForDate(_date, locale: AppLocale.en),
        '2 cups · This month 2/4',
      );
    },
  );

  test(
    'copyWith preserves, replaces, and explicitly clears generated keys',
    () {
      final source = _habit(
        id: 'copy-unit',
        count: 2,
        target: 1,
        generatedUnitKey: 'unknown-key',
      );

      final unchanged = source.copyWith();
      final replaced = source.copyWith(generatedUnitKey: 'cup');
      final cleared = source.copyWith(clearGeneratedUnitKey: true);

      expect(unchanged.generatedUnitKey, 'unknown-key');
      expect(unchanged.toJson()['generatedUnitKey'], 'unknown-key');
      expect(replaced.generatedUnitKey, 'cup');
      expect(replaced.toJson()['generatedUnitKey'], 'cup');
      expect(cleared.generatedUnitKey, isNull);
      expect(cleared.toJson(), isNot(contains('generatedUnitKey')));
      expect(source.generatedUnitKey, 'unknown-key');
    },
  );

  test('locale reads use current copy without mutating model or JSON', () {
    final habit = _habit(
      id: 'locale-read',
      count: 1,
      target: 2,
      generatedUnitKey: 'cup',
    );
    final jsonBefore = jsonEncode(habit.toJson());
    final countBefore = habit.countForDate(_date);
    final unitBefore = habit.unit;
    final keyBefore = habit.generatedUnitKey;

    for (final locale in AppLocale.values) {
      I18n.setLocale(locale);
      expect(
        habit.formatCountForDate(_date),
        locale == AppLocale.zh ? '1 杯 / 2 杯' : '1 cup / 2 cups',
      );
      expect(jsonEncode(habit.toJson()), jsonBefore);
      expect(habit.countForDate(_date), countBefore);
      expect(habit.unit, unitBefore);
      expect(habit.generatedUnitKey, keyBefore);
    }
  });

  test('backup export and import preserve generated unit provenance', () async {
    final preferences = await SharedPreferences.getInstance();
    final habit = _habit(
      id: 'backup-cup',
      count: 2,
      target: 3,
      generatedUnitKey: 'cup',
    );
    await preferences.setString('habits', jsonEncode([habit.toJson()]));

    final backup = await BackupService.exportAll();
    final backupData =
        (jsonDecode(backup) as Map<String, dynamic>)['data']
            as Map<String, dynamic>;
    final storedHabits =
        ((backupData['habits'] as Map<String, dynamic>)['value'] as String);
    final exportedHabit =
        (jsonDecode(storedHabits) as List).single as Map<String, dynamic>;
    expect(exportedHabit['generatedUnitKey'], 'cup');

    await preferences.remove('habits');
    expect(await BackupService.importAll(backup), greaterThan(0));
    final restoredJson =
        (jsonDecode(preferences.getString('habits')!) as List).single
            as Map<String, dynamic>;
    final restored = Habit.fromJson(restoredJson);
    expect(restored.generatedUnitKey, 'cup');
    expect(
      restored.formatCountForDate(_date, locale: AppLocale.en),
      '2 cups / 3 cups',
    );
  });
}

Habit _habit({
  required String id,
  required int count,
  required int target,
  String? unit,
  String? generatedUnitKey,
  HabitKind kind = HabitKind.positive,
  int? flexTarget,
  HabitFlexPeriod? flexPeriod,
  Map<String, int>? completions,
}) => Habit(
  id: id,
  name: 'Habit $id',
  kind: kind,
  targetCount: target,
  unit: unit,
  generatedUnitKey: generatedUnitKey,
  flexTarget: flexTarget,
  flexPeriod: flexPeriod,
  completions: completions ?? {_dateKey: count},
  createdAt: _date,
  updatedAt: _date,
);
