import 'package:flutter_test/flutter_test.dart';

import 'package:duoyi/core/habit_templates.dart';
import 'package:duoyi/core/i18n.dart';

void main() {
  setUp(() {
    I18n.setLocale(AppLocale.zh);
  });

  test('习惯模板按当前语言输出名称和分类', () {
    final first = HabitTemplates.all.first;

    expect(first.localizedName, '每日喝水');
    expect(first.localizedCategory, '身体健康');

    I18n.setLocale(AppLocale.en);
    expect(first.localizedName, 'Drink water');
    expect(first.localizedCategory, 'Health');
  });

  test('英文环境下模板分组不再暴露中文分类', () {
    I18n.setLocale(AppLocale.en);

    final categories = HabitTemplates.byCategory.keys.toSet();

    expect(categories, containsAll(<String>{'Health', 'Learning', 'Life'}));
    expect(categories.any((value) => value.contains('身体')), isFalse);
    expect(categories.any((value) => value.contains('学习')), isFalse);
  });
}
