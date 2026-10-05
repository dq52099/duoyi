import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/brand_strings.dart';

void main() {
  group('提醒通知标题接入品牌文案', () {
    test('default 主题保持历史文案（行为兼容锚点）', () {
      final s = BrandStrings.defaultBrand;
      // 旧派发路径硬编码为「习惯打卡提醒」「今日提醒」；default 主题
      // 必须保持一致，既有行为测试的字面断言才无需改动。
      expect(s.notifHabitRemindTitle, '习惯打卡提醒');
      expect(s.notifTodoDueTitle, '今日提醒');
    });

    test('非 default 主题提供差异化的通知标题', () {
      expect(
        AppBrands.re0.strings.notifHabitRemindTitle,
        isNot(BrandStrings.defaultBrand.notifHabitRemindTitle),
      );
      // re0 的风格化文案。
      expect(AppBrands.re0.strings.notifHabitRemindTitle, '契约提醒');
      expect(AppBrands.genshin.strings.notifHabitRemindTitle, '日常提醒');
    });

    test('reminder_scheduler 派发路径已改读品牌文案', () {
      final source = File(
        'lib/services/reminder_scheduler.dart',
      ).readAsStringSync();

      expect(source, contains("import '../core/brand_strings.dart';"));
      expect(source, contains('void setStrings(BrandStrings strings)'));
      expect(source, contains('_strings.notifHabitRemindTitle'));
      expect(source, contains('_strings.notifTodoDueTitle'));
      // 旧硬编码标题应被移除（default 文案改由品牌词条提供）。
      expect(source, isNot(contains("return '习惯打卡提醒'")));
      expect(source, isNot(contains("=> '今日提醒'")));
    });

    test('notification_service 已有同款注入方法（命名对齐）', () {
      final source = File(
        'lib/providers/notification_service.dart',
      ).readAsStringSync();
      expect(source, contains('void setStrings(BrandStrings s)'));
    });

    test('main.dart 启动与主题切换均向 scheduler 注入品牌文案（接线锚点）', () {
      final source = File('lib/main.dart').readAsStringSync();
      final injections = 'reminderScheduler.setStrings('
          'themeProvider.brand.strings);'.allMatches(source).length;
      expect(
        injections,
        2,
        reason: 'reminderScheduler.setStrings 必须在启动与 '
            'themeProvider.addListener 回调中各注入一次；缺失任一处，'
            '非 default 主题下预约提醒标题将回退 default 文案（死代码回归）',
      );
    });
  });
}
