// NEW988: standalone literal contracts from NEW978, not computed by the app.
// Oracle SHA-256: 0630e416626cdddeb6a99a51c87e52dcd6271ade4f67b6249bff8e686e9c235f.
// 43 API registrations, 199 vectors, 398 frozen zh/en expected literals.
// Source only: not formatted, compiled or executed at authoring time.
import 'package:duoyi/core/habit_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppLocale savedLocale;
  setUp(() {
    savedLocale = I18n.current;
  });
  tearDown(() => I18n.setLocale(savedLocale));

  // weekPrefix: 1 complete NEW978 vectors; old source line 14.
  test('habit weekPrefix preserves 978 literals and locale boundaries', () {
    final vectors = <_InstanceVector>[
      _InstanceVector(
        id: 'literal-0',
        zh: '本周',
        en: 'This week',
        read: (copy) => copy.weekPrefix,
      ),
    ];
    _expectInstanceVectors(vectors);
  });

  // monthPrefix: 1 complete NEW978 vectors; old source line 15.
  test('habit monthPrefix preserves 978 literals and locale boundaries', () {
    final vectors = <_InstanceVector>[
      _InstanceVector(
        id: 'literal-0',
        zh: '本月',
        en: 'This month',
        read: (copy) => copy.monthPrefix,
      ),
    ];
    _expectInstanceVectors(vectors);
  });

  // measurementUnit: 56 complete NEW978 vectors; old source line 18.
  test('habit measurementUnit preserves 978 literals and locale boundaries', () {
    final vectors = <_StaticVector>[
      _StaticVector(
        id: 'selector--1-key0',
        zh: '次',
        en: 'times',
        omitted: () => HabitUiCopy.measurementUnit(-1, authoredUnit: null, generatedUnitKey: null),
        withLocale: (locale) => HabitUiCopy.measurementUnit(-1, authoredUnit: null, generatedUnitKey: null, locale: locale),
      ),
      _StaticVector(
        id: 'selector--1-key1',
        zh: '杯',
        en: 'cups',
        omitted: () => HabitUiCopy.measurementUnit(-1, authoredUnit: null, generatedUnitKey: 'cup'),
        withLocale: (locale) => HabitUiCopy.measurementUnit(-1, authoredUnit: null, generatedUnitKey: 'cup', locale: locale),
      ),
      _StaticVector(
        id: 'selector--1-key2',
        zh: '次',
        en: 'times',
        omitted: () => HabitUiCopy.measurementUnit(-1, authoredUnit: null, generatedUnitKey: 'Cup'),
        withLocale: (locale) => HabitUiCopy.measurementUnit(-1, authoredUnit: null, generatedUnitKey: 'Cup', locale: locale),
      ),
      _StaticVector(
        id: 'selector--1-key3',
        zh: '次',
        en: 'times',
        omitted: () => HabitUiCopy.measurementUnit(-1, authoredUnit: null, generatedUnitKey: ' cup '),
        withLocale: (locale) => HabitUiCopy.measurementUnit(-1, authoredUnit: null, generatedUnitKey: ' cup ', locale: locale),
      ),
      _StaticVector(
        id: 'selector--1-key4',
        zh: '次',
        en: 'times',
        omitted: () => HabitUiCopy.measurementUnit(-1, authoredUnit: null, generatedUnitKey: ''),
        withLocale: (locale) => HabitUiCopy.measurementUnit(-1, authoredUnit: null, generatedUnitKey: '', locale: locale),
      ),
      _StaticVector(
        id: 'selector--1-key5',
        zh: '次',
        en: 'times',
        omitted: () => HabitUiCopy.measurementUnit(-1, authoredUnit: null, generatedUnitKey: 'future-unit'),
        withLocale: (locale) => HabitUiCopy.measurementUnit(-1, authoredUnit: null, generatedUnitKey: 'future-unit', locale: locale),
      ),
      _StaticVector(
        id: 'selector-0-key0',
        zh: '次',
        en: 'times',
        omitted: () => HabitUiCopy.measurementUnit(0, authoredUnit: null, generatedUnitKey: null),
        withLocale: (locale) => HabitUiCopy.measurementUnit(0, authoredUnit: null, generatedUnitKey: null, locale: locale),
      ),
      _StaticVector(
        id: 'selector-0-key1',
        zh: '杯',
        en: 'cups',
        omitted: () => HabitUiCopy.measurementUnit(0, authoredUnit: null, generatedUnitKey: 'cup'),
        withLocale: (locale) => HabitUiCopy.measurementUnit(0, authoredUnit: null, generatedUnitKey: 'cup', locale: locale),
      ),
      _StaticVector(
        id: 'selector-0-key2',
        zh: '次',
        en: 'times',
        omitted: () => HabitUiCopy.measurementUnit(0, authoredUnit: null, generatedUnitKey: 'Cup'),
        withLocale: (locale) => HabitUiCopy.measurementUnit(0, authoredUnit: null, generatedUnitKey: 'Cup', locale: locale),
      ),
      _StaticVector(
        id: 'selector-0-key3',
        zh: '次',
        en: 'times',
        omitted: () => HabitUiCopy.measurementUnit(0, authoredUnit: null, generatedUnitKey: ' cup '),
        withLocale: (locale) => HabitUiCopy.measurementUnit(0, authoredUnit: null, generatedUnitKey: ' cup ', locale: locale),
      ),
      _StaticVector(
        id: 'selector-0-key4',
        zh: '次',
        en: 'times',
        omitted: () => HabitUiCopy.measurementUnit(0, authoredUnit: null, generatedUnitKey: ''),
        withLocale: (locale) => HabitUiCopy.measurementUnit(0, authoredUnit: null, generatedUnitKey: '', locale: locale),
      ),
      _StaticVector(
        id: 'selector-0-key5',
        zh: '次',
        en: 'times',
        omitted: () => HabitUiCopy.measurementUnit(0, authoredUnit: null, generatedUnitKey: 'future-unit'),
        withLocale: (locale) => HabitUiCopy.measurementUnit(0, authoredUnit: null, generatedUnitKey: 'future-unit', locale: locale),
      ),
      _StaticVector(
        id: 'selector-1-key0',
        zh: '次',
        en: 'time',
        omitted: () => HabitUiCopy.measurementUnit(1, authoredUnit: null, generatedUnitKey: null),
        withLocale: (locale) => HabitUiCopy.measurementUnit(1, authoredUnit: null, generatedUnitKey: null, locale: locale),
      ),
      _StaticVector(
        id: 'selector-1-key1',
        zh: '杯',
        en: 'cup',
        omitted: () => HabitUiCopy.measurementUnit(1, authoredUnit: null, generatedUnitKey: 'cup'),
        withLocale: (locale) => HabitUiCopy.measurementUnit(1, authoredUnit: null, generatedUnitKey: 'cup', locale: locale),
      ),
      _StaticVector(
        id: 'selector-1-key2',
        zh: '次',
        en: 'time',
        omitted: () => HabitUiCopy.measurementUnit(1, authoredUnit: null, generatedUnitKey: 'Cup'),
        withLocale: (locale) => HabitUiCopy.measurementUnit(1, authoredUnit: null, generatedUnitKey: 'Cup', locale: locale),
      ),
      _StaticVector(
        id: 'selector-1-key3',
        zh: '次',
        en: 'time',
        omitted: () => HabitUiCopy.measurementUnit(1, authoredUnit: null, generatedUnitKey: ' cup '),
        withLocale: (locale) => HabitUiCopy.measurementUnit(1, authoredUnit: null, generatedUnitKey: ' cup ', locale: locale),
      ),
      _StaticVector(
        id: 'selector-1-key4',
        zh: '次',
        en: 'time',
        omitted: () => HabitUiCopy.measurementUnit(1, authoredUnit: null, generatedUnitKey: ''),
        withLocale: (locale) => HabitUiCopy.measurementUnit(1, authoredUnit: null, generatedUnitKey: '', locale: locale),
      ),
      _StaticVector(
        id: 'selector-1-key5',
        zh: '次',
        en: 'time',
        omitted: () => HabitUiCopy.measurementUnit(1, authoredUnit: null, generatedUnitKey: 'future-unit'),
        withLocale: (locale) => HabitUiCopy.measurementUnit(1, authoredUnit: null, generatedUnitKey: 'future-unit', locale: locale),
      ),
      _StaticVector(
        id: 'selector-1.0-key0',
        zh: '次',
        en: 'time',
        omitted: () => HabitUiCopy.measurementUnit(1.0, authoredUnit: null, generatedUnitKey: null),
        withLocale: (locale) => HabitUiCopy.measurementUnit(1.0, authoredUnit: null, generatedUnitKey: null, locale: locale),
      ),
      _StaticVector(
        id: 'selector-1.0-key1',
        zh: '杯',
        en: 'cup',
        omitted: () => HabitUiCopy.measurementUnit(1.0, authoredUnit: null, generatedUnitKey: 'cup'),
        withLocale: (locale) => HabitUiCopy.measurementUnit(1.0, authoredUnit: null, generatedUnitKey: 'cup', locale: locale),
      ),
      _StaticVector(
        id: 'selector-1.0-key2',
        zh: '次',
        en: 'time',
        omitted: () => HabitUiCopy.measurementUnit(1.0, authoredUnit: null, generatedUnitKey: 'Cup'),
        withLocale: (locale) => HabitUiCopy.measurementUnit(1.0, authoredUnit: null, generatedUnitKey: 'Cup', locale: locale),
      ),
      _StaticVector(
        id: 'selector-1.0-key3',
        zh: '次',
        en: 'time',
        omitted: () => HabitUiCopy.measurementUnit(1.0, authoredUnit: null, generatedUnitKey: ' cup '),
        withLocale: (locale) => HabitUiCopy.measurementUnit(1.0, authoredUnit: null, generatedUnitKey: ' cup ', locale: locale),
      ),
      _StaticVector(
        id: 'selector-1.0-key4',
        zh: '次',
        en: 'time',
        omitted: () => HabitUiCopy.measurementUnit(1.0, authoredUnit: null, generatedUnitKey: ''),
        withLocale: (locale) => HabitUiCopy.measurementUnit(1.0, authoredUnit: null, generatedUnitKey: '', locale: locale),
      ),
      _StaticVector(
        id: 'selector-1.0-key5',
        zh: '次',
        en: 'time',
        omitted: () => HabitUiCopy.measurementUnit(1.0, authoredUnit: null, generatedUnitKey: 'future-unit'),
        withLocale: (locale) => HabitUiCopy.measurementUnit(1.0, authoredUnit: null, generatedUnitKey: 'future-unit', locale: locale),
      ),
      _StaticVector(
        id: 'selector-1.01-key0',
        zh: '次',
        en: 'times',
        omitted: () => HabitUiCopy.measurementUnit(1.01, authoredUnit: null, generatedUnitKey: null),
        withLocale: (locale) => HabitUiCopy.measurementUnit(1.01, authoredUnit: null, generatedUnitKey: null, locale: locale),
      ),
      _StaticVector(
        id: 'selector-1.01-key1',
        zh: '杯',
        en: 'cups',
        omitted: () => HabitUiCopy.measurementUnit(1.01, authoredUnit: null, generatedUnitKey: 'cup'),
        withLocale: (locale) => HabitUiCopy.measurementUnit(1.01, authoredUnit: null, generatedUnitKey: 'cup', locale: locale),
      ),
      _StaticVector(
        id: 'selector-1.01-key2',
        zh: '次',
        en: 'times',
        omitted: () => HabitUiCopy.measurementUnit(1.01, authoredUnit: null, generatedUnitKey: 'Cup'),
        withLocale: (locale) => HabitUiCopy.measurementUnit(1.01, authoredUnit: null, generatedUnitKey: 'Cup', locale: locale),
      ),
      _StaticVector(
        id: 'selector-1.01-key3',
        zh: '次',
        en: 'times',
        omitted: () => HabitUiCopy.measurementUnit(1.01, authoredUnit: null, generatedUnitKey: ' cup '),
        withLocale: (locale) => HabitUiCopy.measurementUnit(1.01, authoredUnit: null, generatedUnitKey: ' cup ', locale: locale),
      ),
      _StaticVector(
        id: 'selector-1.01-key4',
        zh: '次',
        en: 'times',
        omitted: () => HabitUiCopy.measurementUnit(1.01, authoredUnit: null, generatedUnitKey: ''),
        withLocale: (locale) => HabitUiCopy.measurementUnit(1.01, authoredUnit: null, generatedUnitKey: '', locale: locale),
      ),
      _StaticVector(
        id: 'selector-1.01-key5',
        zh: '次',
        en: 'times',
        omitted: () => HabitUiCopy.measurementUnit(1.01, authoredUnit: null, generatedUnitKey: 'future-unit'),
        withLocale: (locale) => HabitUiCopy.measurementUnit(1.01, authoredUnit: null, generatedUnitKey: 'future-unit', locale: locale),
      ),
      _StaticVector(
        id: 'selector-2-key0',
        zh: '次',
        en: 'times',
        omitted: () => HabitUiCopy.measurementUnit(2, authoredUnit: null, generatedUnitKey: null),
        withLocale: (locale) => HabitUiCopy.measurementUnit(2, authoredUnit: null, generatedUnitKey: null, locale: locale),
      ),
      _StaticVector(
        id: 'selector-2-key1',
        zh: '杯',
        en: 'cups',
        omitted: () => HabitUiCopy.measurementUnit(2, authoredUnit: null, generatedUnitKey: 'cup'),
        withLocale: (locale) => HabitUiCopy.measurementUnit(2, authoredUnit: null, generatedUnitKey: 'cup', locale: locale),
      ),
      _StaticVector(
        id: 'selector-2-key2',
        zh: '次',
        en: 'times',
        omitted: () => HabitUiCopy.measurementUnit(2, authoredUnit: null, generatedUnitKey: 'Cup'),
        withLocale: (locale) => HabitUiCopy.measurementUnit(2, authoredUnit: null, generatedUnitKey: 'Cup', locale: locale),
      ),
      _StaticVector(
        id: 'selector-2-key3',
        zh: '次',
        en: 'times',
        omitted: () => HabitUiCopy.measurementUnit(2, authoredUnit: null, generatedUnitKey: ' cup '),
        withLocale: (locale) => HabitUiCopy.measurementUnit(2, authoredUnit: null, generatedUnitKey: ' cup ', locale: locale),
      ),
      _StaticVector(
        id: 'selector-2-key4',
        zh: '次',
        en: 'times',
        omitted: () => HabitUiCopy.measurementUnit(2, authoredUnit: null, generatedUnitKey: ''),
        withLocale: (locale) => HabitUiCopy.measurementUnit(2, authoredUnit: null, generatedUnitKey: '', locale: locale),
      ),
      _StaticVector(
        id: 'selector-2-key5',
        zh: '次',
        en: 'times',
        omitted: () => HabitUiCopy.measurementUnit(2, authoredUnit: null, generatedUnitKey: 'future-unit'),
        withLocale: (locale) => HabitUiCopy.measurementUnit(2, authoredUnit: null, generatedUnitKey: 'future-unit', locale: locale),
      ),
      _StaticVector(
        id: 'selector-2.5-key0',
        zh: '次',
        en: 'times',
        omitted: () => HabitUiCopy.measurementUnit(2.5, authoredUnit: null, generatedUnitKey: null),
        withLocale: (locale) => HabitUiCopy.measurementUnit(2.5, authoredUnit: null, generatedUnitKey: null, locale: locale),
      ),
      _StaticVector(
        id: 'selector-2.5-key1',
        zh: '杯',
        en: 'cups',
        omitted: () => HabitUiCopy.measurementUnit(2.5, authoredUnit: null, generatedUnitKey: 'cup'),
        withLocale: (locale) => HabitUiCopy.measurementUnit(2.5, authoredUnit: null, generatedUnitKey: 'cup', locale: locale),
      ),
      _StaticVector(
        id: 'selector-2.5-key2',
        zh: '次',
        en: 'times',
        omitted: () => HabitUiCopy.measurementUnit(2.5, authoredUnit: null, generatedUnitKey: 'Cup'),
        withLocale: (locale) => HabitUiCopy.measurementUnit(2.5, authoredUnit: null, generatedUnitKey: 'Cup', locale: locale),
      ),
      _StaticVector(
        id: 'selector-2.5-key3',
        zh: '次',
        en: 'times',
        omitted: () => HabitUiCopy.measurementUnit(2.5, authoredUnit: null, generatedUnitKey: ' cup '),
        withLocale: (locale) => HabitUiCopy.measurementUnit(2.5, authoredUnit: null, generatedUnitKey: ' cup ', locale: locale),
      ),
      _StaticVector(
        id: 'selector-2.5-key4',
        zh: '次',
        en: 'times',
        omitted: () => HabitUiCopy.measurementUnit(2.5, authoredUnit: null, generatedUnitKey: ''),
        withLocale: (locale) => HabitUiCopy.measurementUnit(2.5, authoredUnit: null, generatedUnitKey: '', locale: locale),
      ),
      _StaticVector(
        id: 'selector-2.5-key5',
        zh: '次',
        en: 'times',
        omitted: () => HabitUiCopy.measurementUnit(2.5, authoredUnit: null, generatedUnitKey: 'future-unit'),
        withLocale: (locale) => HabitUiCopy.measurementUnit(2.5, authoredUnit: null, generatedUnitKey: 'future-unit', locale: locale),
      ),
      _StaticVector(
        id: 'authored-0-count1',
        zh: '',
        en: '',
        omitted: () => HabitUiCopy.measurementUnit(1, authoredUnit: '', generatedUnitKey: 'cup'),
        withLocale: (locale) => HabitUiCopy.measurementUnit(1, authoredUnit: '', generatedUnitKey: 'cup', locale: locale),
      ),
      _StaticVector(
        id: 'authored-0-count2',
        zh: '',
        en: '',
        omitted: () => HabitUiCopy.measurementUnit(2, authoredUnit: '', generatedUnitKey: 'cup'),
        withLocale: (locale) => HabitUiCopy.measurementUnit(2, authoredUnit: '', generatedUnitKey: 'cup', locale: locale),
      ),
      _StaticVector(
        id: 'authored-1-count1',
        zh: ' ',
        en: ' ',
        omitted: () => HabitUiCopy.measurementUnit(1, authoredUnit: ' ', generatedUnitKey: 'cup'),
        withLocale: (locale) => HabitUiCopy.measurementUnit(1, authoredUnit: ' ', generatedUnitKey: 'cup', locale: locale),
      ),
      _StaticVector(
        id: 'authored-1-count2',
        zh: ' ',
        en: ' ',
        omitted: () => HabitUiCopy.measurementUnit(2, authoredUnit: ' ', generatedUnitKey: 'cup'),
        withLocale: (locale) => HabitUiCopy.measurementUnit(2, authoredUnit: ' ', generatedUnitKey: 'cup', locale: locale),
      ),
      _StaticVector(
        id: 'authored-2-count1',
        zh: '  ',
        en: '  ',
        omitted: () => HabitUiCopy.measurementUnit(1, authoredUnit: '  ', generatedUnitKey: 'cup'),
        withLocale: (locale) => HabitUiCopy.measurementUnit(1, authoredUnit: '  ', generatedUnitKey: 'cup', locale: locale),
      ),
      _StaticVector(
        id: 'authored-2-count2',
        zh: '  ',
        en: '  ',
        omitted: () => HabitUiCopy.measurementUnit(2, authoredUnit: '  ', generatedUnitKey: 'cup'),
        withLocale: (locale) => HabitUiCopy.measurementUnit(2, authoredUnit: '  ', generatedUnitKey: 'cup', locale: locale),
      ),
      _StaticVector(
        id: 'authored-3-count1',
        zh: '次',
        en: '次',
        omitted: () => HabitUiCopy.measurementUnit(1, authoredUnit: '次', generatedUnitKey: 'cup'),
        withLocale: (locale) => HabitUiCopy.measurementUnit(1, authoredUnit: '次', generatedUnitKey: 'cup', locale: locale),
      ),
      _StaticVector(
        id: 'authored-3-count2',
        zh: '次',
        en: '次',
        omitted: () => HabitUiCopy.measurementUnit(2, authoredUnit: '次', generatedUnitKey: 'cup'),
        withLocale: (locale) => HabitUiCopy.measurementUnit(2, authoredUnit: '次', generatedUnitKey: 'cup', locale: locale),
      ),
      _StaticVector(
        id: 'authored-4-count1',
        zh: 'cup',
        en: 'cup',
        omitted: () => HabitUiCopy.measurementUnit(1, authoredUnit: 'cup', generatedUnitKey: 'cup'),
        withLocale: (locale) => HabitUiCopy.measurementUnit(1, authoredUnit: 'cup', generatedUnitKey: 'cup', locale: locale),
      ),
      _StaticVector(
        id: 'authored-4-count2',
        zh: 'cup',
        en: 'cup',
        omitted: () => HabitUiCopy.measurementUnit(2, authoredUnit: 'cup', generatedUnitKey: 'cup'),
        withLocale: (locale) => HabitUiCopy.measurementUnit(2, authoredUnit: 'cup', generatedUnitKey: 'cup', locale: locale),
      ),
      _StaticVector(
        id: 'authored-5-count1',
        zh: 'times',
        en: 'times',
        omitted: () => HabitUiCopy.measurementUnit(1, authoredUnit: 'times', generatedUnitKey: 'cup'),
        withLocale: (locale) => HabitUiCopy.measurementUnit(1, authoredUnit: 'times', generatedUnitKey: 'cup', locale: locale),
      ),
      _StaticVector(
        id: 'authored-5-count2',
        zh: 'times',
        en: 'times',
        omitted: () => HabitUiCopy.measurementUnit(2, authoredUnit: 'times', generatedUnitKey: 'cup'),
        withLocale: (locale) => HabitUiCopy.measurementUnit(2, authoredUnit: 'times', generatedUnitKey: 'cup', locale: locale),
      ),
      _StaticVector(
        id: 'authored-6-count1',
        zh: ' \t 自定义🧭 \n',
        en: ' \t 自定义🧭 \n',
        omitted: () => HabitUiCopy.measurementUnit(1, authoredUnit: ' \t 自定义🧭 \n', generatedUnitKey: 'cup'),
        withLocale: (locale) => HabitUiCopy.measurementUnit(1, authoredUnit: ' \t 自定义🧭 \n', generatedUnitKey: 'cup', locale: locale),
      ),
      _StaticVector(
        id: 'authored-6-count2',
        zh: ' \t 自定义🧭 \n',
        en: ' \t 自定义🧭 \n',
        omitted: () => HabitUiCopy.measurementUnit(2, authoredUnit: ' \t 自定义🧭 \n', generatedUnitKey: 'cup'),
        withLocale: (locale) => HabitUiCopy.measurementUnit(2, authoredUnit: ' \t 自定义🧭 \n', generatedUnitKey: 'cup', locale: locale),
      ),
    ];
    _expectStaticVectors(vectors);
  });

  // weekGoal: 5 complete NEW978 vectors; old source line 40.
  test('habit weekGoal preserves 978 literals and locale boundaries', () {
    final vectors = <_InstanceVector>[
      _InstanceVector(
        id: 'target--1',
        zh: '每周目标: -1 次/周',
        en: 'Weekly goal: -1 times/week',
        read: (copy) => copy.weekGoal(-1),
      ),
      _InstanceVector(
        id: 'target-0',
        zh: '每周目标: 0 次/周',
        en: 'Weekly goal: 0 times/week',
        read: (copy) => copy.weekGoal(0),
      ),
      _InstanceVector(
        id: 'target-1',
        zh: '每周目标: 1 次/周',
        en: 'Weekly goal: 1 time/week',
        read: (copy) => copy.weekGoal(1),
      ),
      _InstanceVector(
        id: 'target-2',
        zh: '每周目标: 2 次/周',
        en: 'Weekly goal: 2 times/week',
        read: (copy) => copy.weekGoal(2),
      ),
      _InstanceVector(
        id: 'target-7',
        zh: '每周目标: 7 次/周',
        en: 'Weekly goal: 7 times/week',
        read: (copy) => copy.weekGoal(7),
      ),
    ];
    _expectInstanceVectors(vectors);
  });

  // monthGoal: 5 complete NEW978 vectors; old source line 44.
  test('habit monthGoal preserves 978 literals and locale boundaries', () {
    final vectors = <_InstanceVector>[
      _InstanceVector(
        id: 'target--1',
        zh: '每月目标: -1 次/月',
        en: 'Monthly goal: -1 times/month',
        read: (copy) => copy.monthGoal(-1),
      ),
      _InstanceVector(
        id: 'target-0',
        zh: '每月目标: 0 次/月',
        en: 'Monthly goal: 0 times/month',
        read: (copy) => copy.monthGoal(0),
      ),
      _InstanceVector(
        id: 'target-1',
        zh: '每月目标: 1 次/月',
        en: 'Monthly goal: 1 time/month',
        read: (copy) => copy.monthGoal(1),
      ),
      _InstanceVector(
        id: 'target-2',
        zh: '每月目标: 2 次/月',
        en: 'Monthly goal: 2 times/month',
        read: (copy) => copy.monthGoal(2),
      ),
      _InstanceVector(
        id: 'target-7',
        zh: '每月目标: 7 次/月',
        en: 'Monthly goal: 7 times/month',
        read: (copy) => copy.monthGoal(7),
      ),
    ];
    _expectInstanceVectors(vectors);
  });

  // weekGoalFor: 5 complete NEW978 vectors; old source line 48.
  test('habit weekGoalFor preserves 978 literals and locale boundaries', () {
    final vectors = <_StaticVector>[
      _StaticVector(
        id: 'target--1',
        zh: '每周目标: -1 次/周',
        en: 'Weekly goal: -1 times/week',
        omitted: () => HabitUiCopy.weekGoalFor(-1),
        withLocale: (locale) => HabitUiCopy.weekGoalFor(-1, locale),
      ),
      _StaticVector(
        id: 'target-0',
        zh: '每周目标: 0 次/周',
        en: 'Weekly goal: 0 times/week',
        omitted: () => HabitUiCopy.weekGoalFor(0),
        withLocale: (locale) => HabitUiCopy.weekGoalFor(0, locale),
      ),
      _StaticVector(
        id: 'target-1',
        zh: '每周目标: 1 次/周',
        en: 'Weekly goal: 1 time/week',
        omitted: () => HabitUiCopy.weekGoalFor(1),
        withLocale: (locale) => HabitUiCopy.weekGoalFor(1, locale),
      ),
      _StaticVector(
        id: 'target-2',
        zh: '每周目标: 2 次/周',
        en: 'Weekly goal: 2 times/week',
        omitted: () => HabitUiCopy.weekGoalFor(2),
        withLocale: (locale) => HabitUiCopy.weekGoalFor(2, locale),
      ),
      _StaticVector(
        id: 'target-7',
        zh: '每周目标: 7 次/周',
        en: 'Weekly goal: 7 times/week',
        omitted: () => HabitUiCopy.weekGoalFor(7),
        withLocale: (locale) => HabitUiCopy.weekGoalFor(7, locale),
      ),
    ];
    _expectStaticVectors(vectors);
  });

  // monthGoalFor: 5 complete NEW978 vectors; old source line 52.
  test('habit monthGoalFor preserves 978 literals and locale boundaries', () {
    final vectors = <_StaticVector>[
      _StaticVector(
        id: 'target--1',
        zh: '每月目标: -1 次/月',
        en: 'Monthly goal: -1 times/month',
        omitted: () => HabitUiCopy.monthGoalFor(-1),
        withLocale: (locale) => HabitUiCopy.monthGoalFor(-1, locale),
      ),
      _StaticVector(
        id: 'target-0',
        zh: '每月目标: 0 次/月',
        en: 'Monthly goal: 0 times/month',
        omitted: () => HabitUiCopy.monthGoalFor(0),
        withLocale: (locale) => HabitUiCopy.monthGoalFor(0, locale),
      ),
      _StaticVector(
        id: 'target-1',
        zh: '每月目标: 1 次/月',
        en: 'Monthly goal: 1 time/month',
        omitted: () => HabitUiCopy.monthGoalFor(1),
        withLocale: (locale) => HabitUiCopy.monthGoalFor(1, locale),
      ),
      _StaticVector(
        id: 'target-2',
        zh: '每月目标: 2 次/月',
        en: 'Monthly goal: 2 times/month',
        omitted: () => HabitUiCopy.monthGoalFor(2),
        withLocale: (locale) => HabitUiCopy.monthGoalFor(2, locale),
      ),
      _StaticVector(
        id: 'target-7',
        zh: '每月目标: 7 次/月',
        en: 'Monthly goal: 7 times/month',
        omitted: () => HabitUiCopy.monthGoalFor(7),
        withLocale: (locale) => HabitUiCopy.monthGoalFor(7, locale),
      ),
    ];
    _expectStaticVectors(vectors);
  });

  // countLabel: 30 complete NEW978 vectors; old source line 56.
  test('habit countLabel preserves 978 literals and locale boundaries', () {
    final vectors = <_InstanceVector>[
      _InstanceVector(
        id: 'branch-0',
        zh: '1 杯 / 2 杯',
        en: '1 cup / 2 cups',
        read: (copy) => copy.countLabel(count: 1, target: 2, negative: false, flexible: false, authoredUnit: null, generatedUnitKey: 'cup', flexProgressLabel: null),
      ),
      _InstanceVector(
        id: 'branch-1',
        zh: '1 杯 · ',
        en: '1 cup · ',
        read: (copy) => copy.countLabel(count: 1, target: 2, negative: false, flexible: false, authoredUnit: null, generatedUnitKey: 'cup', flexProgressLabel: ''),
      ),
      _InstanceVector(
        id: 'branch-2',
        zh: '1 杯 · 本周 2/3 · Raw',
        en: '1 cup · 本周 2/3 · Raw',
        read: (copy) => copy.countLabel(count: 1, target: 2, negative: false, flexible: false, authoredUnit: null, generatedUnitKey: 'cup', flexProgressLabel: '本周 2/3 · Raw'),
      ),
      _InstanceVector(
        id: 'branch-3',
        zh: '1 杯',
        en: '1 cup',
        read: (copy) => copy.countLabel(count: 1, target: 2, negative: false, flexible: true, authoredUnit: null, generatedUnitKey: 'cup', flexProgressLabel: null),
      ),
      _InstanceVector(
        id: 'branch-4',
        zh: '1 杯 · ',
        en: '1 cup · ',
        read: (copy) => copy.countLabel(count: 1, target: 2, negative: false, flexible: true, authoredUnit: null, generatedUnitKey: 'cup', flexProgressLabel: ''),
      ),
      _InstanceVector(
        id: 'branch-5',
        zh: '1 杯 · 本周 2/3 · Raw',
        en: '1 cup · 本周 2/3 · Raw',
        read: (copy) => copy.countLabel(count: 1, target: 2, negative: false, flexible: true, authoredUnit: null, generatedUnitKey: 'cup', flexProgressLabel: '本周 2/3 · Raw'),
      ),
      _InstanceVector(
        id: 'branch-6',
        zh: '已记录 1 杯',
        en: 'Recorded 1 cup',
        read: (copy) => copy.countLabel(count: 1, target: 2, negative: true, flexible: false, authoredUnit: null, generatedUnitKey: 'cup', flexProgressLabel: null),
      ),
      _InstanceVector(
        id: 'branch-7',
        zh: '1 杯 · ',
        en: '1 cup · ',
        read: (copy) => copy.countLabel(count: 1, target: 2, negative: true, flexible: false, authoredUnit: null, generatedUnitKey: 'cup', flexProgressLabel: ''),
      ),
      _InstanceVector(
        id: 'branch-8',
        zh: '1 杯 · 本周 2/3 · Raw',
        en: '1 cup · 本周 2/3 · Raw',
        read: (copy) => copy.countLabel(count: 1, target: 2, negative: true, flexible: false, authoredUnit: null, generatedUnitKey: 'cup', flexProgressLabel: '本周 2/3 · Raw'),
      ),
      _InstanceVector(
        id: 'branch-9',
        zh: '1 杯',
        en: '1 cup',
        read: (copy) => copy.countLabel(count: 1, target: 2, negative: true, flexible: true, authoredUnit: null, generatedUnitKey: 'cup', flexProgressLabel: null),
      ),
      _InstanceVector(
        id: 'branch-10',
        zh: '1 杯 · ',
        en: '1 cup · ',
        read: (copy) => copy.countLabel(count: 1, target: 2, negative: true, flexible: true, authoredUnit: null, generatedUnitKey: 'cup', flexProgressLabel: ''),
      ),
      _InstanceVector(
        id: 'branch-11',
        zh: '1 杯 · 本周 2/3 · Raw',
        en: '1 cup · 本周 2/3 · Raw',
        read: (copy) => copy.countLabel(count: 1, target: 2, negative: true, flexible: true, authoredUnit: null, generatedUnitKey: 'cup', flexProgressLabel: '本周 2/3 · Raw'),
      ),
      _InstanceVector(
        id: 'quantity-12',
        zh: '0 杯 / 1 杯',
        en: '0 cups / 1 cup',
        read: (copy) => copy.countLabel(count: 0, target: 1, negative: false, flexible: false, authoredUnit: null, generatedUnitKey: 'cup', flexProgressLabel: null),
      ),
      _InstanceVector(
        id: 'quantity-13',
        zh: '2 杯 / 1 杯',
        en: '2 cups / 1 cup',
        read: (copy) => copy.countLabel(count: 2, target: 1, negative: false, flexible: false, authoredUnit: null, generatedUnitKey: 'cup', flexProgressLabel: null),
      ),
      _InstanceVector(
        id: 'quantity-14',
        zh: '1 次 / 2 次',
        en: '1 time / 2 times',
        read: (copy) => copy.countLabel(count: 1, target: 2, negative: false, flexible: false, authoredUnit: null, generatedUnitKey: null, flexProgressLabel: null),
      ),
      _InstanceVector(
        id: 'quantity-15',
        zh: '2 次 / 1 次',
        en: '2 times / 1 time',
        read: (copy) => copy.countLabel(count: 2, target: 1, negative: false, flexible: false, authoredUnit: null, generatedUnitKey: null, flexProgressLabel: null),
      ),
      _InstanceVector(
        id: 'quantity-16',
        zh: '-1 杯 / 0 杯',
        en: '-1 cups / 0 cups',
        read: (copy) => copy.countLabel(count: -1, target: 0, negative: false, flexible: false, authoredUnit: null, generatedUnitKey: 'cup', flexProgressLabel: null),
      ),
      _InstanceVector(
        id: 'quantity-17',
        zh: '2 次 / 1 次',
        en: '2 times / 1 time',
        read: (copy) => copy.countLabel(count: 2, target: 1, negative: false, flexible: false, authoredUnit: null, generatedUnitKey: 'unknown-key', flexProgressLabel: null),
      ),
      _InstanceVector(
        id: 'literal-unit-18',
        zh: '2  / 1 ',
        en: '2  / 1 ',
        read: (copy) => copy.countLabel(count: 2, target: 1, negative: false, flexible: false, authoredUnit: '', generatedUnitKey: 'cup', flexProgressLabel: null),
      ),
      _InstanceVector(
        id: 'literal-unit-19',
        zh: '已记录 2 ',
        en: 'Recorded 2 ',
        read: (copy) => copy.countLabel(count: 2, target: 1, negative: true, flexible: false, authoredUnit: '', generatedUnitKey: 'cup', flexProgressLabel: null),
      ),
      _InstanceVector(
        id: 'literal-unit-20',
        zh: '2 ',
        en: '2 ',
        read: (copy) => copy.countLabel(count: 2, target: 1, negative: false, flexible: true, authoredUnit: '', generatedUnitKey: 'cup', flexProgressLabel: null),
      ),
      _InstanceVector(
        id: 'literal-unit-21',
        zh: '2  · ',
        en: '2  · ',
        read: (copy) => copy.countLabel(count: 2, target: 1, negative: false, flexible: false, authoredUnit: '', generatedUnitKey: 'cup', flexProgressLabel: ''),
      ),
      _InstanceVector(
        id: 'literal-unit-22',
        zh: '2    / 1   ',
        en: '2    / 1   ',
        read: (copy) => copy.countLabel(count: 2, target: 1, negative: false, flexible: false, authoredUnit: '  ', generatedUnitKey: 'cup', flexProgressLabel: null),
      ),
      _InstanceVector(
        id: 'literal-unit-23',
        zh: '已记录 2   ',
        en: 'Recorded 2   ',
        read: (copy) => copy.countLabel(count: 2, target: 1, negative: true, flexible: false, authoredUnit: '  ', generatedUnitKey: 'cup', flexProgressLabel: null),
      ),
      _InstanceVector(
        id: 'literal-unit-24',
        zh: '2   ',
        en: '2   ',
        read: (copy) => copy.countLabel(count: 2, target: 1, negative: false, flexible: true, authoredUnit: '  ', generatedUnitKey: 'cup', flexProgressLabel: null),
      ),
      _InstanceVector(
        id: 'literal-unit-25',
        zh: '2    · ',
        en: '2    · ',
        read: (copy) => copy.countLabel(count: 2, target: 1, negative: false, flexible: false, authoredUnit: '  ', generatedUnitKey: 'cup', flexProgressLabel: ''),
      ),
      _InstanceVector(
        id: 'literal-unit-26',
        zh: '2  单位 "\$cash"  / 1  单位 "\$cash" ',
        en: '2  单位 "\$cash"  / 1  单位 "\$cash" ',
        read: (copy) => copy.countLabel(count: 2, target: 1, negative: false, flexible: false, authoredUnit: ' 单位 "\$cash" ', generatedUnitKey: 'cup', flexProgressLabel: null),
      ),
      _InstanceVector(
        id: 'literal-unit-27',
        zh: '已记录 2  单位 "\$cash" ',
        en: 'Recorded 2  单位 "\$cash" ',
        read: (copy) => copy.countLabel(count: 2, target: 1, negative: true, flexible: false, authoredUnit: ' 单位 "\$cash" ', generatedUnitKey: 'cup', flexProgressLabel: null),
      ),
      _InstanceVector(
        id: 'literal-unit-28',
        zh: '2  单位 "\$cash" ',
        en: '2  单位 "\$cash" ',
        read: (copy) => copy.countLabel(count: 2, target: 1, negative: false, flexible: true, authoredUnit: ' 单位 "\$cash" ', generatedUnitKey: 'cup', flexProgressLabel: null),
      ),
      _InstanceVector(
        id: 'literal-unit-29',
        zh: '2  单位 "\$cash"  · ',
        en: '2  单位 "\$cash"  · ',
        read: (copy) => copy.countLabel(count: 2, target: 1, negative: false, flexible: false, authoredUnit: ' 单位 "\$cash" ', generatedUnitKey: 'cup', flexProgressLabel: ''),
      ),
    ];
    _expectInstanceVectors(vectors);
  });

  // actionCancel: 1 complete NEW978 vectors; old source line 84.
  test('habit actionCancel preserves 978 literals and locale boundaries', () {
    final vectors = <_StaticVector>[
      _StaticVector(
        id: 'literal-0',
        zh: '取消',
        en: 'Cancel',
        omitted: () => HabitUiCopy.actionCancel(),
        withLocale: (locale) => HabitUiCopy.actionCancel(locale),
      ),
    ];
    _expectStaticVectors(vectors);
  });

  // actionDelete: 1 complete NEW978 vectors; old source line 87.
  test('habit actionDelete preserves 978 literals and locale boundaries', () {
    final vectors = <_StaticVector>[
      _StaticVector(
        id: 'literal-0',
        zh: '删除',
        en: 'Delete',
        omitted: () => HabitUiCopy.actionDelete(),
        withLocale: (locale) => HabitUiCopy.actionDelete(locale),
      ),
    ];
    _expectStaticVectors(vectors);
  });

  // actionEdit: 1 complete NEW978 vectors; old source line 90.
  test('habit actionEdit preserves 978 literals and locale boundaries', () {
    final vectors = <_StaticVector>[
      _StaticVector(
        id: 'literal-0',
        zh: '编辑',
        en: 'Edit',
        omitted: () => HabitUiCopy.actionEdit(),
        withLocale: (locale) => HabitUiCopy.actionEdit(locale),
      ),
    ];
    _expectStaticVectors(vectors);
  });

  // actionEnd: 1 complete NEW978 vectors; old source line 92.
  test('habit actionEnd preserves 978 literals and locale boundaries', () {
    final vectors = <_StaticVector>[
      _StaticVector(
        id: 'literal-0',
        zh: '结束',
        en: 'End',
        omitted: () => HabitUiCopy.actionEnd(),
        withLocale: (locale) => HabitUiCopy.actionEnd(locale),
      ),
    ];
    _expectStaticVectors(vectors);
  });

  // actionSave: 1 complete NEW978 vectors; old source line 94.
  test('habit actionSave preserves 978 literals and locale boundaries', () {
    final vectors = <_StaticVector>[
      _StaticVector(
        id: 'literal-0',
        zh: '保存',
        en: 'Save',
        omitted: () => HabitUiCopy.actionSave(),
        withLocale: (locale) => HabitUiCopy.actionSave(locale),
      ),
    ];
    _expectStaticVectors(vectors);
  });

  // deleteConfirmTitle: 1 complete NEW978 vectors; old source line 96.
  test('habit deleteConfirmTitle preserves 978 literals and locale boundaries', () {
    final vectors = <_StaticVector>[
      _StaticVector(
        id: 'literal-0',
        zh: '删除习惯？',
        en: 'Delete habit?',
        omitted: () => HabitUiCopy.deleteConfirmTitle(),
        withLocale: (locale) => HabitUiCopy.deleteConfirmTitle(locale),
      ),
    ];
    _expectStaticVectors(vectors);
  });

  // deleteConfirmContent: 3 complete NEW978 vectors; old source line 99.
  test('habit deleteConfirmContent preserves 978 literals and locale boundaries', () {
    final vectors = <_StaticVector>[
      _StaticVector(
        id: 'literal-0',
        zh: '会删除“Habit”和关联记录，不可恢复。',
        en: 'This habit and its records will be permanently deleted.',
        omitted: () => HabitUiCopy.deleteConfirmContent('Habit'),
        withLocale: (locale) => HabitUiCopy.deleteConfirmContent('Habit', locale),
      ),
      _StaticVector(
        id: 'literal-1',
        zh: '会删除“”和关联记录，不可恢复。',
        en: 'This habit and its records will be permanently deleted.',
        omitted: () => HabitUiCopy.deleteConfirmContent(''),
        withLocale: (locale) => HabitUiCopy.deleteConfirmContent('', locale),
      ),
      _StaticVector(
        id: 'literal-2',
        zh: '会删除“  名称 "\$cash" {raw}\n🧭  ”和关联记录，不可恢复。',
        en: 'This habit and its records will be permanently deleted.',
        omitted: () => HabitUiCopy.deleteConfirmContent('  名称 "\$cash" {raw}\n🧭  '),
        withLocale: (locale) => HabitUiCopy.deleteConfirmContent('  名称 "\$cash" {raw}\n🧭  ', locale),
      ),
    ];
    _expectStaticVectors(vectors);
  });

  // endConfirmTitle: 1 complete NEW978 vectors; old source line 104.
  test('habit endConfirmTitle preserves 978 literals and locale boundaries', () {
    final vectors = <_StaticVector>[
      _StaticVector(
        id: 'literal-0',
        zh: '结束习惯？',
        en: 'End habit?',
        omitted: () => HabitUiCopy.endConfirmTitle(),
        withLocale: (locale) => HabitUiCopy.endConfirmTitle(locale),
      ),
    ];
    _expectStaticVectors(vectors);
  });

  // endConfirmContent: 3 complete NEW978 vectors; old source line 107.
  test('habit endConfirmContent preserves 978 literals and locale boundaries', () {
    final vectors = <_StaticVector>[
      _StaticVector(
        id: 'literal-0',
        zh: '结束“Habit”？历史记录将保留。',
        en: 'End "Habit"? Past history will be preserved.',
        omitted: () => HabitUiCopy.endConfirmContent('Habit'),
        withLocale: (locale) => HabitUiCopy.endConfirmContent('Habit', locale),
      ),
      _StaticVector(
        id: 'literal-1',
        zh: '结束“”？历史记录将保留。',
        en: 'End ""? Past history will be preserved.',
        omitted: () => HabitUiCopy.endConfirmContent(''),
        withLocale: (locale) => HabitUiCopy.endConfirmContent('', locale),
      ),
      _StaticVector(
        id: 'literal-2',
        zh: '结束“  名称 "\$cash" {raw}\n🧭  ”？历史记录将保留。',
        en: 'End "  名称 "\$cash" {raw}\n🧭  "? Past history will be preserved.',
        omitted: () => HabitUiCopy.endConfirmContent('  名称 "\$cash" {raw}\n🧭  '),
        withLocale: (locale) => HabitUiCopy.endConfirmContent('  名称 "\$cash" {raw}\n🧭  ', locale),
      ),
    ];
    _expectStaticVectors(vectors);
  });

  // endHabitAction: 1 complete NEW978 vectors; old source line 112.
  test('habit endHabitAction preserves 978 literals and locale boundaries', () {
    final vectors = <_StaticVector>[
      _StaticVector(
        id: 'literal-0',
        zh: '结束习惯',
        en: 'End',
        omitted: () => HabitUiCopy.endHabitAction(),
        withLocale: (locale) => HabitUiCopy.endHabitAction(locale),
      ),
    ];
    _expectStaticVectors(vectors);
  });

  // deleteHabitAction: 1 complete NEW978 vectors; old source line 115.
  test('habit deleteHabitAction preserves 978 literals and locale boundaries', () {
    final vectors = <_StaticVector>[
      _StaticVector(
        id: 'literal-0',
        zh: '删除习惯',
        en: 'Delete',
        omitted: () => HabitUiCopy.deleteHabitAction(),
        withLocale: (locale) => HabitUiCopy.deleteHabitAction(locale),
      ),
    ];
    _expectStaticVectors(vectors);
  });

  // moreActions: 1 complete NEW978 vectors; old source line 118.
  test('habit moreActions preserves 978 literals and locale boundaries', () {
    final vectors = <_StaticVector>[
      _StaticVector(
        id: 'literal-0',
        zh: '更多操作',
        en: 'More',
        omitted: () => HabitUiCopy.moreActions(),
        withLocale: (locale) => HabitUiCopy.moreActions(locale),
      ),
    ];
    _expectStaticVectors(vectors);
  });

  // endedFeedback: 1 complete NEW978 vectors; old source line 121.
  test('habit endedFeedback preserves 978 literals and locale boundaries', () {
    final vectors = <_StaticVector>[
      _StaticVector(
        id: 'literal-0',
        zh: '习惯已结束，历史记录已保留',
        en: 'Habit ended, history preserved',
        omitted: () => HabitUiCopy.endedFeedback(),
        withLocale: (locale) => HabitUiCopy.endedFeedback(locale),
      ),
    ];
    _expectStaticVectors(vectors);
  });

  // deletedFeedback: 1 complete NEW978 vectors; old source line 124.
  test('habit deletedFeedback preserves 978 literals and locale boundaries', () {
    final vectors = <_StaticVector>[
      _StaticVector(
        id: 'literal-0',
        zh: '习惯已删除',
        en: 'Habit deleted',
        omitted: () => HabitUiCopy.deletedFeedback(),
        withLocale: (locale) => HabitUiCopy.deletedFeedback(locale),
      ),
    ];
    _expectStaticVectors(vectors);
  });

  // saveSuccess: 1 complete NEW978 vectors; old source line 127.
  test('habit saveSuccess preserves 978 literals and locale boundaries', () {
    final vectors = <_StaticVector>[
      _StaticVector(
        id: 'literal-0',
        zh: '习惯已保存',
        en: 'Habit saved',
        omitted: () => HabitUiCopy.saveSuccess(),
        withLocale: (locale) => HabitUiCopy.saveSuccess(locale),
      ),
    ];
    _expectStaticVectors(vectors);
  });

  // checkInFailedWithRetry: 1 complete NEW978 vectors; old source line 130.
  test('habit checkInFailedWithRetry preserves 978 literals and locale boundaries', () {
    final vectors = <_StaticVector>[
      _StaticVector(
        id: 'literal-0',
        zh: '打卡失败，请重试',
        en: 'Failed to record check-in. Please try again.',
        omitted: () => HabitUiCopy.checkInFailedWithRetry(),
        withLocale: (locale) => HabitUiCopy.checkInFailedWithRetry(locale),
      ),
    ];
    _expectStaticVectors(vectors);
  });

  // undoFailedWithRetry: 1 complete NEW978 vectors; old source line 134.
  test('habit undoFailedWithRetry preserves 978 literals and locale boundaries', () {
    final vectors = <_StaticVector>[
      _StaticVector(
        id: 'literal-0',
        zh: '撤销打卡失败，请重试',
        en: 'Failed to undo check-in. Please try again.',
        omitted: () => HabitUiCopy.undoFailedWithRetry(),
        withLocale: (locale) => HabitUiCopy.undoFailedWithRetry(locale),
      ),
    ];
    _expectStaticVectors(vectors);
  });

  // saveFailedWithRetry: 1 complete NEW978 vectors; old source line 138.
  test('habit saveFailedWithRetry preserves 978 literals and locale boundaries', () {
    final vectors = <_StaticVector>[
      _StaticVector(
        id: 'literal-0',
        zh: '保存习惯失败，请重试',
        en: 'Failed to save habit. Please try again.',
        omitted: () => HabitUiCopy.saveFailedWithRetry(),
        withLocale: (locale) => HabitUiCopy.saveFailedWithRetry(locale),
      ),
    ];
    _expectStaticVectors(vectors);
  });

  // actionFailedWithRetry: 1 complete NEW978 vectors; old source line 141.
  test('habit actionFailedWithRetry preserves 978 literals and locale boundaries', () {
    final vectors = <_StaticVector>[
      _StaticVector(
        id: 'literal-0',
        zh: '操作失败，请重试',
        en: 'Action failed. Please try again.',
        omitted: () => HabitUiCopy.actionFailedWithRetry(),
        withLocale: (locale) => HabitUiCopy.actionFailedWithRetry(locale),
      ),
    ];
    _expectStaticVectors(vectors);
  });

  // nameRequired: 1 complete NEW978 vectors; old source line 144.
  test('habit nameRequired preserves 978 literals and locale boundaries', () {
    final vectors = <_StaticVector>[
      _StaticVector(
        id: 'literal-0',
        zh: '请输入习惯名称',
        en: 'Please enter a habit name',
        omitted: () => HabitUiCopy.nameRequired(),
        withLocale: (locale) => HabitUiCopy.nameRequired(locale),
      ),
    ];
    _expectStaticVectors(vectors);
  });

  // dailyTargetInvalid: 1 complete NEW978 vectors; old source line 147.
  test('habit dailyTargetInvalid preserves 978 literals and locale boundaries', () {
    final vectors = <_StaticVector>[
      _StaticVector(
        id: 'literal-0',
        zh: '每日目标至少为 1',
        en: 'Daily target must be at least 1',
        omitted: () => HabitUiCopy.dailyTargetInvalid(),
        withLocale: (locale) => HabitUiCopy.dailyTargetInvalid(locale),
      ),
    ];
    _expectStaticVectors(vectors);
  });

  // flexTargetInvalid: 1 complete NEW978 vectors; old source line 150.
  test('habit flexTargetInvalid preserves 978 literals and locale boundaries', () {
    final vectors = <_StaticVector>[
      _StaticVector(
        id: 'literal-0',
        zh: '周期目标至少为 1',
        en: 'Period target must be at least 1',
        omitted: () => HabitUiCopy.flexTargetInvalid(),
        withLocale: (locale) => HabitUiCopy.flexTargetInvalid(locale),
      ),
    ];
    _expectStaticVectors(vectors);
  });

  // dateRangeInvalid: 1 complete NEW978 vectors; old source line 153.
  test('habit dateRangeInvalid preserves 978 literals and locale boundaries', () {
    final vectors = <_StaticVector>[
      _StaticVector(
        id: 'literal-0',
        zh: '结束日期不能早于开始日期',
        en: 'End date cannot be before start date',
        omitted: () => HabitUiCopy.dateRangeInvalid(),
        withLocale: (locale) => HabitUiCopy.dateRangeInvalid(locale),
      ),
    ];
    _expectStaticVectors(vectors);
  });

  // reminderSchedulerMissing: 1 complete NEW978 vectors; old source line 156.
  test('habit reminderSchedulerMissing preserves 978 literals and locale boundaries', () {
    final vectors = <_StaticVector>[
      _StaticVector(
        id: 'literal-0',
        zh: '提醒调度器尚未初始化，请重新打开应用后再保存提醒',
        en: 'Reminder scheduler is not initialized. Please reopen the app before saving reminders.',
        omitted: () => HabitUiCopy.reminderSchedulerMissing(),
        withLocale: (locale) => HabitUiCopy.reminderSchedulerMissing(locale),
      ),
    ];
    _expectStaticVectors(vectors);
  });

  // notificationsNotGranted: 1 complete NEW978 vectors; old source line 160.
  test('habit notificationsNotGranted preserves 978 literals and locale boundaries', () {
    final vectors = <_StaticVector>[
      _StaticVector(
        id: 'literal-0',
        zh: '系统通知未授权，习惯提醒不会响铃或弹出',
        en: 'Notifications not granted. Habit reminders will not sound or pop up',
        omitted: () => HabitUiCopy.notificationsNotGranted(),
        withLocale: (locale) => HabitUiCopy.notificationsNotGranted(locale),
      ),
    ];
    _expectStaticVectors(vectors);
  });

  // reminderPermissionError: 1 complete NEW978 vectors; old source line 164.
  test('habit reminderPermissionError preserves 978 literals and locale boundaries', () {
    final vectors = <_StaticVector>[
      _StaticVector(
        id: 'literal-0',
        zh: '需要系统通知权限以接收提醒',
        en: 'Notification permission is required to set reminders.',
        omitted: () => HabitUiCopy.reminderPermissionError(),
        withLocale: (locale) => HabitUiCopy.reminderPermissionError(locale),
      ),
    ];
    _expectStaticVectors(vectors);
  });

  // reminderRegisterFailed: 1 complete NEW978 vectors; old source line 168.
  test('habit reminderRegisterFailed preserves 978 literals and locale boundaries', () {
    final vectors = <_StaticVector>[
      _StaticVector(
        id: 'literal-0',
        zh: '提醒注册失败',
        en: 'Failed to schedule reminder',
        omitted: () => HabitUiCopy.reminderRegisterFailed(),
        withLocale: (locale) => HabitUiCopy.reminderRegisterFailed(locale),
      ),
    ];
    _expectStaticVectors(vectors);
  });

  // reminderSyncWarning: 3 complete NEW978 vectors; old source line 171.
  test('habit reminderSyncWarning preserves 978 literals and locale boundaries', () {
    final vectors = <_StaticVector>[
      _StaticVector(
        id: 'literal-0',
        zh: '习惯已保存，但提醒未同步：permission not ready',
        en: 'Habit saved, but reminders not synced: permission not ready',
        omitted: () => HabitUiCopy.reminderSyncWarning('permission not ready'),
        withLocale: (locale) => HabitUiCopy.reminderSyncWarning('permission not ready', locale),
      ),
      _StaticVector(
        id: 'literal-1',
        zh: '习惯已保存，但提醒未同步：',
        en: 'Habit saved, but reminders not synced: ',
        omitted: () => HabitUiCopy.reminderSyncWarning(''),
        withLocale: (locale) => HabitUiCopy.reminderSyncWarning('', locale),
      ),
      _StaticVector(
        id: 'literal-2',
        zh: '习惯已保存，但提醒未同步：  未确认 {raw} \$value\n  ',
        en: 'Habit saved, but reminders not synced:   未确认 {raw} \$value\n  ',
        omitted: () => HabitUiCopy.reminderSyncWarning('  未确认 {raw} \$value\n  '),
        withLocale: (locale) => HabitUiCopy.reminderSyncWarning('  未确认 {raw} \$value\n  ', locale),
      ),
    ];
    _expectStaticVectors(vectors);
  });

  // periodGoalReached: 3 complete NEW978 vectors; old source line 176.
  test('habit periodGoalReached preserves 978 literals and locale boundaries', () {
    final vectors = <_StaticVector>[
      _StaticVector(
        id: 'literal-0',
        zh: '「Habit」This week目标已达标',
        en: '"Habit" This week goal reached',
        omitted: () => HabitUiCopy.periodGoalReached('Habit', 'This week'),
        withLocale: (locale) => HabitUiCopy.periodGoalReached('Habit', 'This week', locale),
      ),
      _StaticVector(
        id: 'literal-1',
        zh: '「」目标已达标',
        en: '""  goal reached',
        omitted: () => HabitUiCopy.periodGoalReached('', ''),
        withLocale: (locale) => HabitUiCopy.periodGoalReached('', '', locale),
      ),
      _StaticVector(
        id: 'literal-2',
        zh: '「  名称 "\$cash" {raw}\n🧭  」  Period 原文  目标已达标',
        en: '"  名称 "\$cash" {raw}\n🧭  "   Period 原文   goal reached',
        omitted: () => HabitUiCopy.periodGoalReached('  名称 "\$cash" {raw}\n🧭  ', '  Period 原文  '),
        withLocale: (locale) => HabitUiCopy.periodGoalReached('  名称 "\$cash" {raw}\n🧭  ', '  Period 原文  ', locale),
      ),
    ];
    _expectStaticVectors(vectors);
  });

  // singleSessionGoalReached: 3 complete NEW978 vectors; old source line 184.
  test('habit singleSessionGoalReached preserves 978 literals and locale boundaries', () {
    final vectors = <_StaticVector>[
      _StaticVector(
        id: 'literal-0',
        zh: '「Habit」今日单次目标已完成',
        en: '"Habit" single session goal reached today',
        omitted: () => HabitUiCopy.singleSessionGoalReached('Habit'),
        withLocale: (locale) => HabitUiCopy.singleSessionGoalReached('Habit', locale),
      ),
      _StaticVector(
        id: 'literal-1',
        zh: '「」今日单次目标已完成',
        en: '"" single session goal reached today',
        omitted: () => HabitUiCopy.singleSessionGoalReached(''),
        withLocale: (locale) => HabitUiCopy.singleSessionGoalReached('', locale),
      ),
      _StaticVector(
        id: 'literal-2',
        zh: '「  名称 "\$cash" {raw}\n🧭  」今日单次目标已完成',
        en: '"  名称 "\$cash" {raw}\n🧭  " single session goal reached today',
        omitted: () => HabitUiCopy.singleSessionGoalReached('  名称 "\$cash" {raw}\n🧭  '),
        withLocale: (locale) => HabitUiCopy.singleSessionGoalReached('  名称 "\$cash" {raw}\n🧭  ', locale),
      ),
    ];
    _expectStaticVectors(vectors);
  });

  // checkInSuccessNegative: 3 complete NEW978 vectors; old source line 191.
  test('habit checkInSuccessNegative preserves 978 literals and locale boundaries', () {
    final vectors = <_StaticVector>[
      _StaticVector(
        id: 'literal-0',
        zh: '已记录一次「Habit」',
        en: 'Recorded once for "Habit"',
        omitted: () => HabitUiCopy.checkInSuccessNegative('Habit'),
        withLocale: (locale) => HabitUiCopy.checkInSuccessNegative('Habit', locale),
      ),
      _StaticVector(
        id: 'literal-1',
        zh: '已记录一次「」',
        en: 'Recorded once for ""',
        omitted: () => HabitUiCopy.checkInSuccessNegative(''),
        withLocale: (locale) => HabitUiCopy.checkInSuccessNegative('', locale),
      ),
      _StaticVector(
        id: 'literal-2',
        zh: '已记录一次「  名称 "\$cash" {raw}\n🧭  」',
        en: 'Recorded once for "  名称 "\$cash" {raw}\n🧭  "',
        omitted: () => HabitUiCopy.checkInSuccessNegative('  名称 "\$cash" {raw}\n🧭  '),
        withLocale: (locale) => HabitUiCopy.checkInSuccessNegative('  名称 "\$cash" {raw}\n🧭  ', locale),
      ),
    ];
    _expectStaticVectors(vectors);
  });

  // checkInSuccessStandard: 5 complete NEW978 vectors; old source line 194.
  test('habit checkInSuccessStandard preserves 978 literals and locale boundaries', () {
    final vectors = <_StaticVector>[
      _StaticVector(
        id: 'supplied-boolean-0',
        zh: '「Habit」今日已达标',
        en: '"Habit" goal reached today',
        omitted: () => HabitUiCopy.checkInSuccessStandard('Habit', 0, 5, true),
        withLocale: (locale) => HabitUiCopy.checkInSuccessStandard('Habit', 0, 5, true, locale),
      ),
      _StaticVector(
        id: 'supplied-boolean-1',
        zh: '已打卡「Habit」 9/1',
        en: 'Checked in "Habit" 9/1',
        omitted: () => HabitUiCopy.checkInSuccessStandard('Habit', 9, 1, false),
        withLocale: (locale) => HabitUiCopy.checkInSuccessStandard('Habit', 9, 1, false, locale),
      ),
      _StaticVector(
        id: 'supplied-boolean-2',
        zh: '已打卡「」 1/1',
        en: 'Checked in "" 1/1',
        omitted: () => HabitUiCopy.checkInSuccessStandard('', 1, 1, false),
        withLocale: (locale) => HabitUiCopy.checkInSuccessStandard('', 1, 1, false, locale),
      ),
      _StaticVector(
        id: 'supplied-boolean-3',
        zh: '「  "\$cash" 原文  」今日已达标',
        en: '"  "\$cash" 原文  " goal reached today',
        omitted: () => HabitUiCopy.checkInSuccessStandard('  "\$cash" 原文  ', 1, 1, true),
        withLocale: (locale) => HabitUiCopy.checkInSuccessStandard('  "\$cash" 原文  ', 1, 1, true, locale),
      ),
      _StaticVector(
        id: 'supplied-boolean-4',
        zh: '已打卡「Habit」 -1/0',
        en: 'Checked in "Habit" -1/0',
        omitted: () => HabitUiCopy.checkInSuccessStandard('Habit', -1, 0, false),
        withLocale: (locale) => HabitUiCopy.checkInSuccessStandard('Habit', -1, 0, false, locale),
      ),
    ];
    _expectStaticVectors(vectors);
  });

  // checkInSuccessFlex: 33 complete NEW978 vectors; old source line 211.
  test('habit checkInSuccessFlex preserves 978 literals and locale boundaries', () {
    final vectors = <_StaticVector>[
      _StaticVector(
        id: 'null-empty-bool-prefix-0',
        zh: '已打卡「Habit "\$cash" 原文」 2/3',
        en: 'Checked in "Habit "\$cash" 原文" 2/3',
        omitted: () => HabitUiCopy.checkInSuccessFlex('Habit "\$cash" 原文', 2, 3, null, false, null),
        withLocale: (locale) => HabitUiCopy.checkInSuccessFlex('Habit "\$cash" 原文', 2, 3, null, false, null, locale),
      ),
      _StaticVector(
        id: 'null-empty-bool-prefix-1',
        zh: '已打卡「Habit "\$cash" 原文」 2/3',
        en: 'Checked in "Habit "\$cash" 原文" 2/3',
        omitted: () => HabitUiCopy.checkInSuccessFlex('Habit "\$cash" 原文', 2, 3, null, false, ''),
        withLocale: (locale) => HabitUiCopy.checkInSuccessFlex('Habit "\$cash" 原文', 2, 3, null, false, '', locale),
      ),
      _StaticVector(
        id: 'null-empty-bool-prefix-2',
        zh: '已打卡「Habit "\$cash" 原文」 2/3',
        en: 'Checked in "Habit "\$cash" 原文" 2/3',
        omitted: () => HabitUiCopy.checkInSuccessFlex('Habit "\$cash" 原文', 2, 3, null, false, '  '),
        withLocale: (locale) => HabitUiCopy.checkInSuccessFlex('Habit "\$cash" 原文', 2, 3, null, false, '  ', locale),
      ),
      _StaticVector(
        id: 'null-empty-bool-prefix-3',
        zh: '已打卡「Habit "\$cash" 原文」 2/3',
        en: 'Checked in "Habit "\$cash" 原文" 2/3',
        omitted: () => HabitUiCopy.checkInSuccessFlex('Habit "\$cash" 原文', 2, 3, null, false, 'MonthRaw'),
        withLocale: (locale) => HabitUiCopy.checkInSuccessFlex('Habit "\$cash" 原文', 2, 3, null, false, 'MonthRaw', locale),
      ),
      _StaticVector(
        id: 'null-empty-bool-prefix-4',
        zh: '已打卡「Habit "\$cash" 原文」 2/3',
        en: 'Checked in "Habit "\$cash" 原文" 2/3',
        omitted: () => HabitUiCopy.checkInSuccessFlex('Habit "\$cash" 原文', 2, 3, null, true, null),
        withLocale: (locale) => HabitUiCopy.checkInSuccessFlex('Habit "\$cash" 原文', 2, 3, null, true, null, locale),
      ),
      _StaticVector(
        id: 'null-empty-bool-prefix-5',
        zh: '已打卡「Habit "\$cash" 原文」 2/3',
        en: 'Checked in "Habit "\$cash" 原文" 2/3',
        omitted: () => HabitUiCopy.checkInSuccessFlex('Habit "\$cash" 原文', 2, 3, null, true, ''),
        withLocale: (locale) => HabitUiCopy.checkInSuccessFlex('Habit "\$cash" 原文', 2, 3, null, true, '', locale),
      ),
      _StaticVector(
        id: 'null-empty-bool-prefix-6',
        zh: '已打卡「Habit "\$cash" 原文」 2/3',
        en: 'Checked in "Habit "\$cash" 原文" 2/3',
        omitted: () => HabitUiCopy.checkInSuccessFlex('Habit "\$cash" 原文', 2, 3, null, true, '  '),
        withLocale: (locale) => HabitUiCopy.checkInSuccessFlex('Habit "\$cash" 原文', 2, 3, null, true, '  ', locale),
      ),
      _StaticVector(
        id: 'null-empty-bool-prefix-7',
        zh: '已打卡「Habit "\$cash" 原文」 2/3',
        en: 'Checked in "Habit "\$cash" 原文" 2/3',
        omitted: () => HabitUiCopy.checkInSuccessFlex('Habit "\$cash" 原文', 2, 3, null, true, 'MonthRaw'),
        withLocale: (locale) => HabitUiCopy.checkInSuccessFlex('Habit "\$cash" 原文', 2, 3, null, true, 'MonthRaw', locale),
      ),
      _StaticVector(
        id: 'null-empty-bool-prefix-8',
        zh: '已打卡「Habit "\$cash" 原文」 ',
        en: 'Checked in "Habit "\$cash" 原文" ',
        omitted: () => HabitUiCopy.checkInSuccessFlex('Habit "\$cash" 原文', 2, 3, '', false, null),
        withLocale: (locale) => HabitUiCopy.checkInSuccessFlex('Habit "\$cash" 原文', 2, 3, '', false, null, locale),
      ),
      _StaticVector(
        id: 'null-empty-bool-prefix-9',
        zh: '已打卡「Habit "\$cash" 原文」 ',
        en: 'Checked in "Habit "\$cash" 原文" ',
        omitted: () => HabitUiCopy.checkInSuccessFlex('Habit "\$cash" 原文', 2, 3, '', false, ''),
        withLocale: (locale) => HabitUiCopy.checkInSuccessFlex('Habit "\$cash" 原文', 2, 3, '', false, '', locale),
      ),
      _StaticVector(
        id: 'null-empty-bool-prefix-10',
        zh: '已打卡「Habit "\$cash" 原文」 ',
        en: 'Checked in "Habit "\$cash" 原文" ',
        omitted: () => HabitUiCopy.checkInSuccessFlex('Habit "\$cash" 原文', 2, 3, '', false, '  '),
        withLocale: (locale) => HabitUiCopy.checkInSuccessFlex('Habit "\$cash" 原文', 2, 3, '', false, '  ', locale),
      ),
      _StaticVector(
        id: 'null-empty-bool-prefix-11',
        zh: '已打卡「Habit "\$cash" 原文」 ',
        en: 'Checked in "Habit "\$cash" 原文" ',
        omitted: () => HabitUiCopy.checkInSuccessFlex('Habit "\$cash" 原文', 2, 3, '', false, 'MonthRaw'),
        withLocale: (locale) => HabitUiCopy.checkInSuccessFlex('Habit "\$cash" 原文', 2, 3, '', false, 'MonthRaw', locale),
      ),
      _StaticVector(
        id: 'null-empty-bool-prefix-12',
        zh: '「Habit "\$cash" 原文」本周期目标已达标',
        en: '"Habit "\$cash" 原文" Period goal reached',
        omitted: () => HabitUiCopy.checkInSuccessFlex('Habit "\$cash" 原文', 2, 3, '', true, null),
        withLocale: (locale) => HabitUiCopy.checkInSuccessFlex('Habit "\$cash" 原文', 2, 3, '', true, null, locale),
      ),
      _StaticVector(
        id: 'null-empty-bool-prefix-13',
        zh: '「Habit "\$cash" 原文」目标已达标',
        en: '"Habit "\$cash" 原文"  goal reached',
        omitted: () => HabitUiCopy.checkInSuccessFlex('Habit "\$cash" 原文', 2, 3, '', true, ''),
        withLocale: (locale) => HabitUiCopy.checkInSuccessFlex('Habit "\$cash" 原文', 2, 3, '', true, '', locale),
      ),
      _StaticVector(
        id: 'null-empty-bool-prefix-14',
        zh: '「Habit "\$cash" 原文」  目标已达标',
        en: '"Habit "\$cash" 原文"    goal reached',
        omitted: () => HabitUiCopy.checkInSuccessFlex('Habit "\$cash" 原文', 2, 3, '', true, '  '),
        withLocale: (locale) => HabitUiCopy.checkInSuccessFlex('Habit "\$cash" 原文', 2, 3, '', true, '  ', locale),
      ),
      _StaticVector(
        id: 'null-empty-bool-prefix-15',
        zh: '「Habit "\$cash" 原文」MonthRaw目标已达标',
        en: '"Habit "\$cash" 原文" MonthRaw goal reached',
        omitted: () => HabitUiCopy.checkInSuccessFlex('Habit "\$cash" 原文', 2, 3, '', true, 'MonthRaw'),
        withLocale: (locale) => HabitUiCopy.checkInSuccessFlex('Habit "\$cash" 原文', 2, 3, '', true, 'MonthRaw', locale),
      ),
      _StaticVector(
        id: 'null-empty-bool-prefix-16',
        zh: '已打卡「Habit "\$cash" 原文」   ',
        en: 'Checked in "Habit "\$cash" 原文"   ',
        omitted: () => HabitUiCopy.checkInSuccessFlex('Habit "\$cash" 原文', 2, 3, '  ', false, null),
        withLocale: (locale) => HabitUiCopy.checkInSuccessFlex('Habit "\$cash" 原文', 2, 3, '  ', false, null, locale),
      ),
      _StaticVector(
        id: 'null-empty-bool-prefix-17',
        zh: '已打卡「Habit "\$cash" 原文」   ',
        en: 'Checked in "Habit "\$cash" 原文"   ',
        omitted: () => HabitUiCopy.checkInSuccessFlex('Habit "\$cash" 原文', 2, 3, '  ', false, ''),
        withLocale: (locale) => HabitUiCopy.checkInSuccessFlex('Habit "\$cash" 原文', 2, 3, '  ', false, '', locale),
      ),
      _StaticVector(
        id: 'null-empty-bool-prefix-18',
        zh: '已打卡「Habit "\$cash" 原文」   ',
        en: 'Checked in "Habit "\$cash" 原文"   ',
        omitted: () => HabitUiCopy.checkInSuccessFlex('Habit "\$cash" 原文', 2, 3, '  ', false, '  '),
        withLocale: (locale) => HabitUiCopy.checkInSuccessFlex('Habit "\$cash" 原文', 2, 3, '  ', false, '  ', locale),
      ),
      _StaticVector(
        id: 'null-empty-bool-prefix-19',
        zh: '已打卡「Habit "\$cash" 原文」   ',
        en: 'Checked in "Habit "\$cash" 原文"   ',
        omitted: () => HabitUiCopy.checkInSuccessFlex('Habit "\$cash" 原文', 2, 3, '  ', false, 'MonthRaw'),
        withLocale: (locale) => HabitUiCopy.checkInSuccessFlex('Habit "\$cash" 原文', 2, 3, '  ', false, 'MonthRaw', locale),
      ),
      _StaticVector(
        id: 'null-empty-bool-prefix-20',
        zh: '「Habit "\$cash" 原文」本周期目标已达标',
        en: '"Habit "\$cash" 原文" Period goal reached',
        omitted: () => HabitUiCopy.checkInSuccessFlex('Habit "\$cash" 原文', 2, 3, '  ', true, null),
        withLocale: (locale) => HabitUiCopy.checkInSuccessFlex('Habit "\$cash" 原文', 2, 3, '  ', true, null, locale),
      ),
      _StaticVector(
        id: 'null-empty-bool-prefix-21',
        zh: '「Habit "\$cash" 原文」目标已达标',
        en: '"Habit "\$cash" 原文"  goal reached',
        omitted: () => HabitUiCopy.checkInSuccessFlex('Habit "\$cash" 原文', 2, 3, '  ', true, ''),
        withLocale: (locale) => HabitUiCopy.checkInSuccessFlex('Habit "\$cash" 原文', 2, 3, '  ', true, '', locale),
      ),
      _StaticVector(
        id: 'null-empty-bool-prefix-22',
        zh: '「Habit "\$cash" 原文」  目标已达标',
        en: '"Habit "\$cash" 原文"    goal reached',
        omitted: () => HabitUiCopy.checkInSuccessFlex('Habit "\$cash" 原文', 2, 3, '  ', true, '  '),
        withLocale: (locale) => HabitUiCopy.checkInSuccessFlex('Habit "\$cash" 原文', 2, 3, '  ', true, '  ', locale),
      ),
      _StaticVector(
        id: 'null-empty-bool-prefix-23',
        zh: '「Habit "\$cash" 原文」MonthRaw目标已达标',
        en: '"Habit "\$cash" 原文" MonthRaw goal reached',
        omitted: () => HabitUiCopy.checkInSuccessFlex('Habit "\$cash" 原文', 2, 3, '  ', true, 'MonthRaw'),
        withLocale: (locale) => HabitUiCopy.checkInSuccessFlex('Habit "\$cash" 原文', 2, 3, '  ', true, 'MonthRaw', locale),
      ),
      _StaticVector(
        id: 'null-empty-bool-prefix-24',
        zh: '已打卡「Habit "\$cash" 原文」 本周 2/3 {raw}',
        en: 'Checked in "Habit "\$cash" 原文" 本周 2/3 {raw}',
        omitted: () => HabitUiCopy.checkInSuccessFlex('Habit "\$cash" 原文', 2, 3, '本周 2/3 {raw}', false, null),
        withLocale: (locale) => HabitUiCopy.checkInSuccessFlex('Habit "\$cash" 原文', 2, 3, '本周 2/3 {raw}', false, null, locale),
      ),
      _StaticVector(
        id: 'null-empty-bool-prefix-25',
        zh: '已打卡「Habit "\$cash" 原文」 本周 2/3 {raw}',
        en: 'Checked in "Habit "\$cash" 原文" 本周 2/3 {raw}',
        omitted: () => HabitUiCopy.checkInSuccessFlex('Habit "\$cash" 原文', 2, 3, '本周 2/3 {raw}', false, ''),
        withLocale: (locale) => HabitUiCopy.checkInSuccessFlex('Habit "\$cash" 原文', 2, 3, '本周 2/3 {raw}', false, '', locale),
      ),
      _StaticVector(
        id: 'null-empty-bool-prefix-26',
        zh: '已打卡「Habit "\$cash" 原文」 本周 2/3 {raw}',
        en: 'Checked in "Habit "\$cash" 原文" 本周 2/3 {raw}',
        omitted: () => HabitUiCopy.checkInSuccessFlex('Habit "\$cash" 原文', 2, 3, '本周 2/3 {raw}', false, '  '),
        withLocale: (locale) => HabitUiCopy.checkInSuccessFlex('Habit "\$cash" 原文', 2, 3, '本周 2/3 {raw}', false, '  ', locale),
      ),
      _StaticVector(
        id: 'null-empty-bool-prefix-27',
        zh: '已打卡「Habit "\$cash" 原文」 本周 2/3 {raw}',
        en: 'Checked in "Habit "\$cash" 原文" 本周 2/3 {raw}',
        omitted: () => HabitUiCopy.checkInSuccessFlex('Habit "\$cash" 原文', 2, 3, '本周 2/3 {raw}', false, 'MonthRaw'),
        withLocale: (locale) => HabitUiCopy.checkInSuccessFlex('Habit "\$cash" 原文', 2, 3, '本周 2/3 {raw}', false, 'MonthRaw', locale),
      ),
      _StaticVector(
        id: 'null-empty-bool-prefix-28',
        zh: '「Habit "\$cash" 原文」本周期目标已达标',
        en: '"Habit "\$cash" 原文" Period goal reached',
        omitted: () => HabitUiCopy.checkInSuccessFlex('Habit "\$cash" 原文', 2, 3, '本周 2/3 {raw}', true, null),
        withLocale: (locale) => HabitUiCopy.checkInSuccessFlex('Habit "\$cash" 原文', 2, 3, '本周 2/3 {raw}', true, null, locale),
      ),
      _StaticVector(
        id: 'null-empty-bool-prefix-29',
        zh: '「Habit "\$cash" 原文」目标已达标',
        en: '"Habit "\$cash" 原文"  goal reached',
        omitted: () => HabitUiCopy.checkInSuccessFlex('Habit "\$cash" 原文', 2, 3, '本周 2/3 {raw}', true, ''),
        withLocale: (locale) => HabitUiCopy.checkInSuccessFlex('Habit "\$cash" 原文', 2, 3, '本周 2/3 {raw}', true, '', locale),
      ),
      _StaticVector(
        id: 'null-empty-bool-prefix-30',
        zh: '「Habit "\$cash" 原文」  目标已达标',
        en: '"Habit "\$cash" 原文"    goal reached',
        omitted: () => HabitUiCopy.checkInSuccessFlex('Habit "\$cash" 原文', 2, 3, '本周 2/3 {raw}', true, '  '),
        withLocale: (locale) => HabitUiCopy.checkInSuccessFlex('Habit "\$cash" 原文', 2, 3, '本周 2/3 {raw}', true, '  ', locale),
      ),
      _StaticVector(
        id: 'null-empty-bool-prefix-31',
        zh: '「Habit "\$cash" 原文」MonthRaw目标已达标',
        en: '"Habit "\$cash" 原文" MonthRaw goal reached',
        omitted: () => HabitUiCopy.checkInSuccessFlex('Habit "\$cash" 原文', 2, 3, '本周 2/3 {raw}', true, 'MonthRaw'),
        withLocale: (locale) => HabitUiCopy.checkInSuccessFlex('Habit "\$cash" 原文', 2, 3, '本周 2/3 {raw}', true, 'MonthRaw', locale),
      ),
      _StaticVector(
        id: 'supplied-false-above-target',
        zh: '已打卡「Habit」 raw progress 99/1',
        en: 'Checked in "Habit" raw progress 99/1',
        omitted: () => HabitUiCopy.checkInSuccessFlex('Habit', 99, 1, 'raw progress 99/1', false, 'Month'),
        withLocale: (locale) => HabitUiCopy.checkInSuccessFlex('Habit', 99, 1, 'raw progress 99/1', false, 'Month', locale),
      ),
    ];
    _expectStaticVectors(vectors);
  });

  // dateRecordFeedback: 5 complete NEW978 vectors; old source line 238.
  test('habit dateRecordFeedback preserves 978 literals and locale boundaries', () {
    final vectors = <_StaticVector>[
      _StaticVector(
        id: 'literal-0',
        zh: '已记录「Habit」',
        en: 'Recorded for "Habit"',
        omitted: () => HabitUiCopy.dateRecordFeedback('Habit', DateTime(2026, 10, 15)),
        withLocale: (locale) => HabitUiCopy.dateRecordFeedback('Habit', DateTime(2026, 10, 15), locale),
      ),
      _StaticVector(
        id: 'literal-1',
        zh: '已记录「」',
        en: 'Recorded for ""',
        omitted: () => HabitUiCopy.dateRecordFeedback('', DateTime(2026, 10, 15)),
        withLocale: (locale) => HabitUiCopy.dateRecordFeedback('', DateTime(2026, 10, 15), locale),
      ),
      _StaticVector(
        id: 'literal-2',
        zh: '已记录「  名称 "\$cash" {raw}\n🧭  」',
        en: 'Recorded for "  名称 "\$cash" {raw}\n🧭  "',
        omitted: () => HabitUiCopy.dateRecordFeedback('  名称 "\$cash" {raw}\n🧭  ', DateTime(2026, 10, 15)),
        withLocale: (locale) => HabitUiCopy.dateRecordFeedback('  名称 "\$cash" {raw}\n🧭  ', DateTime(2026, 10, 15), locale),
      ),
      _StaticVector(
        id: 'unused-date-0',
        zh: '已记录「Habit」',
        en: 'Recorded for "Habit"',
        omitted: () => HabitUiCopy.dateRecordFeedback('Habit', DateTime(1999, 1, 2, 23, 59, 59)),
        withLocale: (locale) => HabitUiCopy.dateRecordFeedback('Habit', DateTime(1999, 1, 2, 23, 59, 59), locale),
      ),
      _StaticVector(
        id: 'unused-date-1',
        zh: '已记录「Habit」',
        en: 'Recorded for "Habit"',
        omitted: () => HabitUiCopy.dateRecordFeedback('Habit', DateTime.utc(2035, 12, 31, 12, 34, 56)),
        withLocale: (locale) => HabitUiCopy.dateRecordFeedback('Habit', DateTime.utc(2035, 12, 31, 12, 34, 56), locale),
      ),
    ];
    _expectStaticVectors(vectors);
  });

  // dateUndoFeedback: 5 complete NEW978 vectors; old source line 244.
  test('habit dateUndoFeedback preserves 978 literals and locale boundaries', () {
    final vectors = <_StaticVector>[
      _StaticVector(
        id: 'literal-0',
        zh: '已撤销「Habit」记录',
        en: 'Check-in undone for "Habit"',
        omitted: () => HabitUiCopy.dateUndoFeedback('Habit', DateTime(2026, 10, 15)),
        withLocale: (locale) => HabitUiCopy.dateUndoFeedback('Habit', DateTime(2026, 10, 15), locale),
      ),
      _StaticVector(
        id: 'literal-1',
        zh: '已撤销「」记录',
        en: 'Check-in undone for ""',
        omitted: () => HabitUiCopy.dateUndoFeedback('', DateTime(2026, 10, 15)),
        withLocale: (locale) => HabitUiCopy.dateUndoFeedback('', DateTime(2026, 10, 15), locale),
      ),
      _StaticVector(
        id: 'literal-2',
        zh: '已撤销「  名称 "\$cash" {raw}\n🧭  」记录',
        en: 'Check-in undone for "  名称 "\$cash" {raw}\n🧭  "',
        omitted: () => HabitUiCopy.dateUndoFeedback('  名称 "\$cash" {raw}\n🧭  ', DateTime(2026, 10, 15)),
        withLocale: (locale) => HabitUiCopy.dateUndoFeedback('  名称 "\$cash" {raw}\n🧭  ', DateTime(2026, 10, 15), locale),
      ),
      _StaticVector(
        id: 'unused-date-0',
        zh: '已撤销「Habit」记录',
        en: 'Check-in undone for "Habit"',
        omitted: () => HabitUiCopy.dateUndoFeedback('Habit', DateTime(1999, 1, 2, 23, 59, 59)),
        withLocale: (locale) => HabitUiCopy.dateUndoFeedback('Habit', DateTime(1999, 1, 2, 23, 59, 59), locale),
      ),
      _StaticVector(
        id: 'unused-date-1',
        zh: '已撤销「Habit」记录',
        en: 'Check-in undone for "Habit"',
        omitted: () => HabitUiCopy.dateUndoFeedback('Habit', DateTime.utc(2035, 12, 31, 12, 34, 56)),
        withLocale: (locale) => HabitUiCopy.dateUndoFeedback('Habit', DateTime.utc(2035, 12, 31, 12, 34, 56), locale),
      ),
    ];
    _expectStaticVectors(vectors);
  });

}

class _StaticVector {
  const _StaticVector({
    required this.id,
    required this.zh,
    required this.en,
    required this.omitted,
    required this.withLocale,
  });

  final String id;
  final String zh;
  final String en;
  final String Function() omitted;
  final String Function(AppLocale?) withLocale;
}

class _InstanceVector {
  const _InstanceVector({
    required this.id,
    required this.zh,
    required this.en,
    required this.read,
  });

  final String id;
  final String zh;
  final String en;
  final String Function(HabitUiCopy) read;
}

void _expectStaticVectors(List<_StaticVector> vectors) {
  var notifications = 0;
  void onLocaleChanged() => notifications++;
  I18n.localeListenable.addListener(onLocaleChanged);
  try {
    for (final current in [AppLocale.zh, AppLocale.en, AppLocale.zh]) {
      I18n.setLocale(current);
      for (final vector in vectors) {
        final currentExpected = current == AppLocale.zh ? vector.zh : vector.en;
        _expectPureRead(
          vector.omitted,
          currentExpected,
          current,
          () => notifications,
          '${vector.id}: omitted locale',
        );
        _expectPureRead(
          () => vector.withLocale(null),
          currentExpected,
          current,
          () => notifications,
          '${vector.id}: null locale',
        );
        _expectPureRead(
          () => vector.withLocale(AppLocale.zh),
          vector.zh,
          current,
          () => notifications,
          '${vector.id}: explicit zh',
        );
        _expectPureRead(
          () => vector.withLocale(AppLocale.en),
          vector.en,
          current,
          () => notifications,
          '${vector.id}: explicit en',
        );
      }
    }
  } finally {
    I18n.localeListenable.removeListener(onLocaleChanged);
  }
}

void _expectInstanceVectors(List<_InstanceVector> vectors) {
  const retainedZh = HabitUiCopy(AppLocale.zh);
  const retainedEn = HabitUiCopy(AppLocale.en);
  var notifications = 0;
  void onLocaleChanged() => notifications++;
  I18n.localeListenable.addListener(onLocaleChanged);
  try {
    for (final current in [AppLocale.zh, AppLocale.en, AppLocale.zh]) {
      I18n.setLocale(current);
      for (final vector in vectors) {
        _expectPureRead(
          () => vector.read(retainedZh),
          vector.zh,
          current,
          () => notifications,
          '${vector.id}: retained zh instance',
        );
        _expectPureRead(
          () => vector.read(retainedEn),
          vector.en,
          current,
          () => notifications,
          '${vector.id}: retained en instance',
        );
      }
    }
  } finally {
    I18n.localeListenable.removeListener(onLocaleChanged);
  }
}

void _expectPureRead(
  String Function() read,
  String expected,
  AppLocale current,
  int Function() notificationCount,
  String reason,
) {
  final notificationsBefore = notificationCount();
  expect(read(), expected, reason: reason);
  expect(I18n.current, current, reason: '$reason must not change current locale');
  expect(
    I18n.localeListenable.value,
    current,
    reason: '$reason must not change locale notifier value',
  );
  expect(
    notificationCount(),
    notificationsBefore,
    reason: '$reason must not notify locale listeners',
  );
}
