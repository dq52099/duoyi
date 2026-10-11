import 'package:duoyi/services/widget_calendar_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WidgetCalendarLink civil dates', () {
    for (final entry in {
      '0001-01-01': DateTime(1, 1, 1),
      '1900-02-28': DateTime(1900, 2, 28),
      '2000-02-29': DateTime(2000, 2, 29),
      '2024-02-29': DateTime(2024, 2, 29),
      '2026-01-01': DateTime(2026, 1, 1),
      '2026-12-31': DateTime(2026, 12, 31),
      '9999-12-31': DateTime(9999, 12, 31),
    }.entries) {
      test('accepts ${entry.key} as a local day', () {
        final uri = Uri(
          scheme: 'duoyi',
          host: 'calendar',
          queryParameters: {'date': entry.key},
        );
        expect(WidgetCalendarLink.hasDateRequest(uri), isTrue);
        final date = WidgetCalendarLink.dateFromUri(uri);
        expect(date, entry.value);
        expect(date!.isUtc, isFalse);
      });
    }

    for (final text in [
      '',
      '0000-01-01',
      '10000-01-01',
      '1900-02-29',
      '2025-02-29',
      '2026-02-30',
      '2026-00-01',
      '2026-13-01',
      '2026-01-00',
      '2026-01-32',
      '2026-1-01',
      '2026-01-1',
      ' 2026-01-01',
      '2026-01-01 ',
      '2026-01-01T00:00:00Z',
      '٢٠٢٦-01-01',
    ]) {
      test('rejects invalid date text "$text"', () {
        final uri = Uri(
          scheme: 'duoyi',
          host: 'calendar',
          queryParameters: {'date': text},
        );
        expect(WidgetCalendarLink.hasDateRequest(uri), isTrue);
        expect(WidgetCalendarLink.dateFromUri(uri), isNull);
      });
    }

    for (final link in [
      'https://calendar?date=2026-01-01',
      'duoyi:calendar?date=2026-01-01',
      'duoyi://todo?date=2026-01-01',
      'duoyi://user@calendar?date=2026-01-01',
      'duoyi://calendar:1234?date=2026-01-01',
      'duoyi://calendar/month?date=2026-01-01',
      'duoyi://calendar/?date=2026-01-01',
      'duoyi://calendar?date=2026-01-01#fragment',
      'duoyi://calendar?date=2026-01-01&unknown=value',
      'duoyi://calendar?date=%FF',
      'duoyi://calendar?date=2026-01-01&source=%FF',
    ]) {
      test('rejects unsupported date URI $link', () {
        expect(WidgetCalendarLink.dateFromUri(Uri.parse(link)), isNull);
      });
    }

    for (final key in [
      'date',
      'source',
      'widget_delivery',
      'widget_day',
      'widget_offset',
      'widget_account',
    ]) {
      test('rejects duplicate $key in either ordering', () {
        final first = key == 'date' ? '2026-01-01' : 'first';
        final second = key == 'date' ? '2026-01-02' : 'second';
        for (final values in [
          [first, second],
          [second, first],
        ]) {
          final uri = Uri(
            scheme: 'duoyi',
            host: 'calendar',
            queryParameters: {
              'date': ['2026-01-01'],
              key: values,
            },
          );
          expect(WidgetCalendarLink.dateFromUri(uri), isNull);
        }
      });
    }

    test('accepts singleton native transport and snapshot fields', () {
      final uri = Uri.parse(
        'duoyi://calendar?date=2026-01-01&source=widget&widget_delivery=tap-1'
        '&widget_day=2026-01-02&widget_offset=480&widget_account=owner',
      );
      expect(WidgetCalendarLink.dateFromUri(uri), DateTime(2026, 1, 1));
    });

    test('root and missing date preserve section navigation', () {
      for (final link in [
        'duoyi://calendar',
        'duoyi://calendar?source=widget&widget_delivery=root-1',
      ]) {
        final uri = Uri.parse(link);
        expect(WidgetCalendarLink.hasDateRequest(uri), isFalse);
        expect(WidgetCalendarLink.dateFromUri(uri), isNull);
      }
    });
  });
}
