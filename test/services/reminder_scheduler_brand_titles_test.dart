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
      // 注入逻辑收敛为共享函数 pushBrandStringsToNotifiers：启动、
      // themeProvider.addListener 与 localeProvider.addListener 三处都必须
      // 经过它——语言切换同样会改变 AppBrand.strings（BrandStrings.forLocale
      // 按 I18n 分发），缺失任一处，非 default 主题或英文语言下预约提醒
      // 标题将回退 default 中文文案（死代码回归）。
      const fnName = 'pushBrandStringsToNotifiers';
      final anchor = source.indexOf('void $fnName() {');
      expect(anchor, greaterThanOrEqualTo(0), reason: '缺少品牌文案注入共享函数 $fnName');
      final bodyEnd = source.indexOf('themeProvider.addListener', anchor);
      expect(bodyEnd, greaterThan(anchor));
      final body = source.substring(anchor, bodyEnd);
      expect(
        body,
        contains('reminderScheduler.setStrings(themeProvider.brand.strings)'),
        reason: '$fnName 必须向 scheduler 注入品牌文案',
      );
      expect(
        body,
        contains('notificationService.setStrings(themeProvider.brand.strings)'),
        reason: '$fnName 必须向 notificationService 注入品牌文案',
      );
      final calls = '$fnName();'.allMatches(source).length;
      expect(
        calls,
        3,
        reason:
            '$fnName 必须在启动、themeProvider.addListener 与 '
            'localeProvider.addListener 三处各直调一次',
      );
      // locale 监听除重推文案外，还需重推小组件数据（payload 文案随语言）。
      final localeAnchor = source.indexOf('localeProvider.addListener(() {');
      expect(localeAnchor, greaterThan(anchor), reason: '语言切换必须重推品牌文案并刷新小组件');
      final localeBlockEnd = source.indexOf('});', localeAnchor);
      expect(localeBlockEnd, greaterThan(localeAnchor));
      final localeBlock = source.substring(localeAnchor, localeBlockEnd);
      expect(localeBlock, contains('$fnName();'));
      expect(localeBlock, contains('queueHomeWidgetPush();'));
    });
  });
}
