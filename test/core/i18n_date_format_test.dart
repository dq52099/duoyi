import 'package:flutter_test/flutter_test.dart';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/i18n_date_format.dart';

void main() {
  setUp(() {
    I18n.setLocale(AppLocale.zh);
  });

  group('I18nDateFormat', () {
    test('中文完整日期时间符合 R17 样例', () {
      I18n.setLocale(AppLocale.zh);
      final value = DateTime(2026, 5, 15, 15);

      expect(I18nDateFormat.fullDateTime(value), '2026年5月15日 周五 15:00');
    });

    test('英文完整日期时间使用英文月份和 12 小时制', () {
      I18n.setLocale(AppLocale.en);
      final value = DateTime(2026, 5, 15, 15);

      expect(I18nDateFormat.fullDateTime(value), 'May 15, 2026 Fri 3:00 PM');
    });

    test('智能日期在无时间时只展示日期', () {
      final value = DateTime(2026, 5, 15, 15);

      expect(I18nDateFormat.smartDate(value, includeTime: false), '2026年5月15日');

      I18n.setLocale(AppLocale.en);
      expect(
        I18nDateFormat.smartDate(value, includeTime: false),
        'May 15, 2026',
      );
    });

    test('短日期时间可省略午夜时间', () {
      final midnight = DateTime(2026, 5, 15);
      final afternoon = DateTime(2026, 5, 15, 15, 30);

      expect(
        I18nDateFormat.compactDateTime(midnight, omitTimeWhenMidnight: true),
        '5月15日',
      );
      expect(
        I18nDateFormat.compactDateTime(afternoon, omitTimeWhenMidnight: true),
        '5月15日 15:30',
      );

      I18n.setLocale(AppLocale.en);
      expect(
        I18nDateFormat.compactDateTime(midnight, omitTimeWhenMidnight: true),
        'May 15',
      );
      expect(
        I18nDateFormat.compactDateTime(afternoon, omitTimeWhenMidnight: true),
        'May 15 3:30 PM',
      );
    });

    test('月日星期和纯时间跟随语言', () {
      final value = DateTime(2026, 5, 15, 9, 5);

      expect(I18nDateFormat.monthDayWithWeekday(value), '5月15日 · 周五');
      expect(I18nDateFormat.timeOfDay(hour: 9, minute: 5), '09:05');

      I18n.setLocale(AppLocale.en);
      expect(I18nDateFormat.monthDayWithWeekday(value), 'May 15 · Fri');
      expect(I18nDateFormat.timeOfDay(hour: 9, minute: 5), '9:05 AM');
    });
  });
}
