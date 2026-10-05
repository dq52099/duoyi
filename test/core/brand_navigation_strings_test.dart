import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/brand_strings.dart';

void main() {
  group('BrandStrings 导航与问候词条（9 套主题）', () {
    test('每套主题提供全部 7 个底导航标签，且不为空', () {
      expect(AppBrands.all, hasLength(9), reason: '应有 9 套主题');
      for (final brand in AppBrands.all) {
        final s = brand.strings;
        final labels = <String, String>{
          'navToday': s.navToday,
          'navTodo': s.navTodo,
          'navHabit': s.navHabit,
          'navCalendar': s.navCalendar,
          'navFocus': s.navFocus,
          'navWidget': s.navWidget,
          'navMine': s.navMine,
        };
        labels.forEach((name, value) {
          expect(value.trim(), isNotEmpty, reason: '${brand.id}.$name 不应为空');
        });
      }
    });

    test('每套主题提供 4 个时段问候语，且不为空', () {
      for (final brand in AppBrands.all) {
        final s = brand.strings;
        for (final value in <String>[
          s.greetingMorning,
          s.greetingNoon,
          s.greetingAfternoon,
          s.greetingEvening,
        ]) {
          expect(value.trim(), isNotEmpty, reason: '${brand.id} 问候语不应为空');
        }
      }
    });

    test('greetingFor 按时段取词：深夜归入晚间问候', () {
      final s = AppBrands.defaultBrand.strings;
      expect(s.greetingFor(DateTime(2026, 1, 1, 2)), s.greetingEvening);
      expect(s.greetingFor(DateTime(2026, 1, 1, 7)), s.greetingMorning);
      expect(s.greetingFor(DateTime(2026, 1, 1, 13)), s.greetingNoon);
      expect(s.greetingFor(DateTime(2026, 1, 1, 15)), s.greetingAfternoon);
      expect(s.greetingFor(DateTime(2026, 1, 1, 20)), s.greetingEvening);
    });

    test('不同主题的导航标签文案不同（换主题应换文案）', () {
      final themes = <String, BrandStrings>{
        'default': AppBrands.defaultBrand.strings,
        're0': AppBrands.re0.strings,
        'genshin': AppBrands.genshin.strings,
        'starRail': AppBrands.starRail.strings,
        'wuthering': AppBrands.wuthering.strings,
        'zzz': AppBrands.zzz.strings,
        'yanyun': AppBrands.yanyun.strings,
        'botw': AppBrands.botw.strings,
        'liquidGlass': AppBrands.liquidGlass.strings,
      };
      expect(themes['default']!.navTodo, '待办');
      expect(themes['re0']!.navTodo, isNot('待办'));
      expect(themes['re0']!.navToday, isNot(themes['default']!.navToday));
    });

    test('液态玻璃主题词条齐备且走 iOS 简洁中文', () {
      final s = AppBrands.liquidGlass.strings;
      expect(BrandStrings.forStyle(BrandStyle.liquidGlass), same(s));
      expect(s.navToday, '今天');
      expect(s.todoCreateTitle, '新待办');
      expect(s.appTitle, isNot(AppBrands.defaultBrand.strings.appTitle));
      for (final value in <String>[
        s.todoTitle,
        s.todoEmpty,
        s.habitCreateTitle,
        s.calendarQuickAddTitle,
        s.focusTitle,
        s.mineProductivityScore,
        s.notifPomodoroDoneTitle,
        s.notifHabitRemindTitle,
      ]) {
        expect(value.trim(), isNotEmpty, reason: 'liquidGlass 词条不应为空');
      }
    });
  });

  group('消费端静态锚点', () {
    test('main.dart 底导航标签消费 BrandStrings.nav*，不再读 i18n nav.*', () {
      final main = File('lib/main.dart').readAsStringSync();
      for (final field in const [
        'navToday',
        'navTodo',
        'navHabit',
        'navCalendar',
        'navFocus',
        'navWidget',
        'navMine',
      ]) {
        expect(
          main,
          contains('label: brand.$field'),
          reason: 'main.dart 应使用 brand.$field',
        );
      }
      expect(
        main,
        isNot(contains("label: I18n.tr('nav.")),
        reason: '底导航标签不应再固定读 i18n，主题换文案才对导航生效',
      );
    });

    test('today_screen 问候语走 brand.greetingFor，user_profile 不再内置问候', () {
      final today = File('lib/screens/today_screen.dart').readAsStringSync();
      expect(today, contains('s.greetingFor(now)'));
      expect(
        today,
        isNot(contains('user.profile.greeting')),
        reason: '问候语不应再来自 user_profile 的固定文案',
      );

      final profile = File('lib/models/user_profile.dart').readAsStringSync();
      expect(profile, isNot(contains('String get greeting')));
    });
  });
}
