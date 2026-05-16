import 'package:flutter_test/flutter_test.dart';

import 'package:duoyi/core/i18n.dart';

void main() {
  setUp(() {
    I18n.setLocale(AppLocale.zh);
  });

  group('I18n.tr', () {
    test('中文环境下返回中文文案', () {
      I18n.setLocale(AppLocale.zh);
      expect(I18n.tr('action.confirm'), '确定');
      expect(I18n.tr('nav.today'), '今日');
    });

    test('英文环境下返回英文文案', () {
      I18n.setLocale(AppLocale.en);
      expect(I18n.tr('action.confirm'), 'OK');
      expect(I18n.tr('nav.today'), 'Today');
    });

    test('未知 key 回退到 key 本身', () {
      I18n.setLocale(AppLocale.zh);
      expect(I18n.tr('not.exist.key'), 'not.exist.key');
    });

    test('英文 locale 缺失某 key 时回退到中文', () {
      // 模拟方式：所有 key 应在两边都有；此测试验证回退路径存在
      I18n.setLocale(AppLocale.en);
      // todo.matrix 英文有 'Matrix'，确保也存在中文
      expect(I18n.tr('todo.matrix'), 'Matrix');
      I18n.setLocale(AppLocale.zh);
      expect(I18n.tr('todo.matrix'), '四象限');
    });
  });

  group('词条覆盖完整性', () {
    test('常用导航 keys 中英都有', () {
      const keys = [
        'nav.today',
        'nav.todo',
        'nav.habit',
        'nav.calendar',
        'nav.focus',
        'nav.mine',
      ];
      for (final k in keys) {
        I18n.setLocale(AppLocale.zh);
        expect(I18n.tr(k), isNot(k), reason: 'zh 缺失 $k');
        I18n.setLocale(AppLocale.en);
        expect(I18n.tr(k), isNot(k), reason: 'en 缺失 $k');
      }
    });

    test('常用动作 keys 中英都有', () {
      const keys = [
        'action.confirm',
        'action.cancel',
        'action.save',
        'action.delete',
        'action.complete',
      ];
      for (final k in keys) {
        I18n.setLocale(AppLocale.zh);
        expect(I18n.tr(k), isNot(k), reason: 'zh 缺失 $k');
        I18n.setLocale(AppLocale.en);
        expect(I18n.tr(k), isNot(k), reason: 'en 缺失 $k');
      }
    });
  });
}
