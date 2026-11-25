import 'package:duoyi/core/almanac_ui_copy.dart';
import 'package:duoyi/core/calendar_agenda_ui_copy.dart';
import 'package:duoyi/core/heatmap_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/i18n_date_format.dart';
import 'package:duoyi/core/statistics_ui_copy.dart';
import 'package:duoyi/models/recurrence.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => I18n.setLocale(AppLocale.zh));
  final sample = DateTime.utc(2026, 5, 15, 15, 4);
  const dates = {
    'yyyy-MM-dd': '2026-05-15',
    'MM/dd/yyyy': '05/15/2026',
    'dd/MM/yyyy': '15/05/2026',
    'yyyy年M月d日': '2026年5月15日',
  };
  for (final locale in AppLocale.values) {
    for (final entry in dates.entries) {
      test(
        '${locale.name} ${entry.key}: pure copies use the explicit date contract',
        () {
          I18n.setLocale(locale == AppLocale.en ? AppLocale.zh : AppLocale.en);
          final date = I18nDateFormat.date(
            sample,
            pattern: entry.key,
            locale: locale,
          );
          expect(date, entry.value);
          expect(
            I18nDateFormat.fullDateTime(
              sample,
              pattern: entry.key,
              locale: locale,
            ),
            '${entry.value} ${locale == AppLocale.en ? 'Fri 3:04 PM' : '周五 15:04'}',
          );
          expect(
            StatisticsUiCopy(locale, datePattern: entry.key).formatDate(sample),
            entry.value,
          );
          expect(
            HeatmapUiCopy(locale).range(sample, sample, pattern: entry.key),
            '${entry.value} – ${entry.value}',
          );
          expect(
            AlmanacUiCopy.fullDateTitle(sample, locale, entry.key),
            startsWith(entry.value),
          );
        },
      );
      test(
        '${locale.name} ${entry.key}: calendar semantics and recurrence preserve dates',
        () {
          I18n.setLocale(locale);
          final semantic = CalendarAgendaUiCopy.daySemanticLabel(
            sample,
            isToday: true,
            isSelected: true,
            eventCount: 1,
            subText: null,
            pattern: entry.key,
          );
          expect(semantic, startsWith(entry.value));
          final rule = RecurrenceRule(
            frequency: RecurrenceFrequency.daily,
            endDate: sample,
          );
          expect(
            rule.displayLabel(datePattern: entry.key),
            contains(entry.value),
          );
          expect(rule.toJson()['endDate'], sample.toIso8601String());
          expect(sample, DateTime.utc(2026, 5, 15, 15, 4));
        },
      );
    }
  }
  for (final pattern in I18nDateFormat.supportedPatterns) {
    test('$pattern: skipped Apia civil day preserves December 30', () {
      final civil = DateTime.utc(2011, 12, 30);
      final expected = I18nDateFormat.date(
        civil,
        pattern: pattern,
        locale: AppLocale.en,
      );
      I18n.setLocale(AppLocale.zh);
      expect(
        AlmanacUiCopy.skippedCivilDayTitle(2011, 12, 30, AppLocale.en, pattern),
        expected,
      );
      expect(
        AlmanacUiCopy.skippedDateFullTitle(civil, AppLocale.en, pattern),
        '$expected · Unavailable',
      );
      expect(civil.day, 30);
    });
  }
  test(
    'invalid patterns normalize and absent patterns retain locale formatting',
    () {
      I18n.setLocale(AppLocale.en);
      expect(I18nDateFormat.date(sample), 'May 15, 2026');
      for (final pattern in ['', 'yyyy/MM/dd', 'bogus']) {
        expect(I18nDateFormat.date(sample, pattern: pattern), '2026-05-15');
        expect(I18nDateFormat.normalizePattern(pattern), 'yyyy-MM-dd');
      }
      expect(I18nDateFormat.normalizePattern(null), 'yyyy-MM-dd');
    },
  );
  test('year padding, leap dates and UTC components remain exact', () {
    expect(
      I18nDateFormat.date(DateTime.utc(1, 1, 2), pattern: 'yyyy-MM-dd'),
      '0001-01-02',
    );
    expect(
      I18nDateFormat.date(DateTime.utc(9999, 12, 31), pattern: 'dd/MM/yyyy'),
      '31/12/9999',
    );
    expect(
      I18nDateFormat.date(DateTime.utc(2024, 2, 29), pattern: 'MM/dd/yyyy'),
      '02/29/2024',
    );
  });
  test(
    'compact, month, and clock formatting remain independent of full-date patterns',
    () {
      I18n.setLocale(AppLocale.en);
      for (final pattern in I18nDateFormat.supportedPatterns) {
        I18nDateFormat.date(sample, pattern: pattern);
        expect(I18nDateFormat.monthDay(sample), 'May 15');
        expect(I18nDateFormat.yearMonth(sample), 'May 2026');
        expect(I18nDateFormat.time(sample), '3:04 PM');
        expect(I18nDateFormat.shortDateTime(sample), 'May 15 3:04 PM');
      }
    },
  );
}
