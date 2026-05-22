import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('习惯模板库覆盖 6 类 30 个推荐模板', () {
    final source = File('lib/core/habit_templates.dart').readAsStringSync();
    final templateCount = RegExp(
      r'^\s{4}HabitTemplate\(',
      multiLine: true,
    ).allMatches(source).length;
    final categories = RegExp(
      r"category: '([^']+)'",
    ).allMatches(source).map((m) => m.group(1)!).toList();

    expect(templateCount, 30);
    expect(categories.toSet(), {
      '身体健康',
      '学习提升',
      '心理调节',
      '生活习惯',
      '社交沟通',
      '职业发展',
    });
    for (final category in categories.toSet()) {
      expect(
        categories.where((value) => value == category),
        hasLength(5),
        reason: '$category 应有 5 个模板',
      );
    }
    expect(source, contains("categoryEn: 'Health'"));
    expect(source, contains("categoryEn: 'Learning'"));
    expect(source, contains("categoryEn: 'Mindfulness'"));
    expect(source, contains("categoryEn: 'Life'"));
    expect(source, contains("categoryEn: 'Social'"));
    expect(source, contains("categoryEn: 'Career'"));
  });

  test('习惯模板包含每日与弹性周/月推荐频率', () {
    final source = File('lib/core/habit_templates.dart').readAsStringSync();

    expect(source, contains('String get localizedFrequencyLabel'));
    expect(source, contains('String get localizedUnit'));
    expect(source, contains('bool get hasFlexRule'));
    expect(source, contains('HabitFlexPeriod.week'));
    expect(source, contains('HabitFlexPeriod.month'));
    expect(source, contains("unit: '杯'"));
    expect(source, contains("unitEn: 'cups'"));
    expect(source, contains("id: 'habit.networking'"));
    expect(source, contains("id: 'habit.coding_practice'"));
  });
}
