import 'dart:io';

import 'package:duoyi/core/calendar_agenda_ui_copy.dart';
import 'package:duoyi/core/calendar_date_navigation.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => I18n.setLocale(AppLocale.zh));

  for (var first = 1; first <= 7; first++) {
    test(
      'ISO week start $first rotates civil days and bilingual headers together',
      () {
        final order = CalendarDateNavigation.orderedWeekdays(first);
        expect(order, [
          for (var col = 0; col < 7; col++) (first - 1 + col) % 7 + 1,
        ]);
        final date = DateTime(2024, 9, 4, 23, 59);
        final days = CalendarDateNavigation.weekDays(
          date,
          firstDayOfWeek: first,
        );
        expect(days, hasLength(7));
        expect(days.map((d) => d!.weekday), order);
        expect(days.where((d) => d!.day == 4), hasLength(1));
        for (var i = 1; i < 7; i++) {
          final prev = days[i - 1]!;
          final current = days[i]!;
          expect(
            DateTime.utc(
              current.year,
              current.month,
              current.day,
            ).difference(DateTime.utc(prev.year, prev.month, prev.day)),
            const Duration(days: 1),
          );
        }
        for (final locale in AppLocale.values) {
          I18n.setLocale(locale);
          final monday = CalendarAgendaUiCopy.weekdayInitials;
          expect(CalendarAgendaUiCopy.weekdayInitialsFor(first), [
            for (final iso in order) monday[iso - 1],
          ]);
        }
      },
    );
  }

  test('invalid display starts use Monday without clamping to Sunday', () {
    for (final value in [-9223372036854775808, -1, 0, 8, 9223372036854775807]) {
      expect(CalendarDateNavigation.normalizeFirstDayOfWeek(value), 1);
      expect(CalendarDateNavigation.orderedWeekdays(value), [
        1,
        2,
        3,
        4,
        5,
        6,
        7,
      ]);
      expect(
        CalendarDateNavigation.weekDays(
          DateTime(2024, 9, 4),
          firstDayOfWeek: value,
        ),
        CalendarDateNavigation.weekDays(DateTime(2024, 9, 4)),
      );
    }
  });

  test('Sunday weeks keep seven slots at both civil year boundaries', () {
    final first = CalendarDateNavigation.weekDays(
      DateTime(1, 1, 1),
      firstDayOfWeek: 7,
    );
    expect(first.first, isNull);
    expect(first.skip(1).map((d) => d!.day), [1, 2, 3, 4, 5, 6]);
    final last = CalendarDateNavigation.weekDays(
      DateTime(9999, 12, 31),
      firstDayOfWeek: 7,
    );
    expect(last.take(6).map((d) => d!.day), [26, 27, 28, 29, 30, 31]);
    expect(last.last, isNull);
  });

  if (Platform.environment['DUOYI_REQUIRE_APIA'] == '1') {
    test('Sunday week retains the absent Apia Friday slot', () {
      final days = CalendarDateNavigation.weekDays(
        DateTime(2011, 12, 28),
        firstDayOfWeek: 7,
      );
      expect(days.map((d) => d?.day), [25, 26, 27, 28, 29, null, 31]);
      expect(days.whereType<DateTime>().map((d) => d.weekday), [
        7,
        1,
        2,
        3,
        4,
        6,
      ]);
    });
  }

  if (Platform.environment['DUOYI_REQUIRE_DST'] == '1') {
    test('all starts preserve civil order around local DST changes', () {
      var offset = DateTime(2024, 1, 1, 12).timeZoneOffset;
      var transitions = 0;
      for (var ordinal = 2; ordinal <= 366; ordinal++) {
        final date = DateTime(2024, 1, ordinal, 12);
        if (date.timeZoneOffset != offset) {
          transitions++;
          for (var first = 1; first <= 7; first++) {
            final days = CalendarDateNavigation.weekDays(
              date,
              firstDayOfWeek: first,
            );
            expect(
              days.map((d) => d!.weekday),
              CalendarDateNavigation.orderedWeekdays(first),
            );
            expect(
              days.map((d) => '${d!.year}-${d.month}-${d.day}').toSet(),
              hasLength(7),
            );
          }
        }
        offset = date.timeZoneOffset;
      }
      expect(transitions, greaterThanOrEqualTo(2));
    });
  }
}
