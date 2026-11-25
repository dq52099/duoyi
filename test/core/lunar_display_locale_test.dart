import 'package:duoyi/core/almanac_locale_format.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/lunar_calendar.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => I18n.setLocale(AppLocale.zh));

  test(
    'lunar year keeps Chinese picker context and romanizes English cycle',
    () {
      expect(
        AlmanacLocaleFormat.formatLunarYear(2026, locale: AppLocale.zh),
        '丙午年（2026）',
      );
      expect(
        AlmanacLocaleFormat.formatLunarYear(2026, locale: AppLocale.en),
        '2026 (Bing-Wu)',
      );
      expect(
        AlmanacLocaleFormat.formatLunarYear(
          2023,
          solarYear: 2024,
          locale: AppLocale.zh,
        ),
        '癸卯年（2024）',
      );
      expect(
        AlmanacLocaleFormat.formatLunarYear(
          2023,
          solarYear: 2024,
          locale: AppLocale.en,
        ),
        '2023 (Gui-Mao)',
      );
      for (final year in [1, 1899, 1900, 2023, 2024, 2025, 2026, 2099]) {
        final english = AlmanacLocaleFormat.formatLunarYear(
          year,
          locale: AppLocale.en,
        );
        expect(english, matches(RegExp(r'^\d+ \([A-Za-z]+-[A-Za-z]+\)$')));
        expect(english, isNot(matches(RegExp(r'[\u3400-\u9fff]'))));
      }
    },
  );

  for (final leap in [false, true]) {
    test('full lunar date follows live locale and preserves leap=$leap', () {
      final date = LunarDate(2023, 2, 1, isLeapMonth: leap);
      for (final locale in [AppLocale.zh, AppLocale.en, AppLocale.zh]) {
        I18n.setLocale(locale);
        if (locale == AppLocale.zh) {
          expect(
            AlmanacLocaleFormat.formatFullLunarDate(date),
            date.toString(),
          );
          expect(
            AlmanacLocaleFormat.formatFullLunarDate(date, includeGanzhi: true),
            '癸卯年（2023）${date.chineseText}',
          );
          expect(AlmanacLocaleFormat.formatLunarDay(date), '初一');
        } else {
          final month = leap ? 'Leap Month' : 'Month';
          expect(
            AlmanacLocaleFormat.formatFullLunarDate(date),
            '2023, $month 2, Day 1',
          );
          expect(
            AlmanacLocaleFormat.formatFullLunarDate(date, includeGanzhi: true),
            '2023 (Gui-Mao), $month 2, Day 1',
          );
          expect(AlmanacLocaleFormat.formatLunarDay(date), 'Day 1');
        }
        // Explicit locale is independent of the live global selection.
        expect(
          AlmanacLocaleFormat.formatFullLunarDate(date, locale: AppLocale.en),
          contains('Day 1'),
        );
        expect(date.toString(), '2023年${leap ? '闰' : ''}二月初一');
        expect(date.isLeapMonth, leap);
      }
    });
  }

  test('lunar year differs from solar year at Chinese New Year boundary', () {
    final lunar = LunarCalendar.fromSolar(DateTime(2024, 1, 1));
    expect(lunar.year, 2023);
    expect(
      AlmanacLocaleFormat.formatFullLunarDate(lunar, locale: AppLocale.en),
      startsWith('2023, Month'),
    );
    expect(
      AlmanacLocaleFormat.formatLunarYear(
        lunar.year,
        solarYear: 2024,
        locale: AppLocale.zh,
      ),
      '癸卯年（2024）',
    );
  });
}
