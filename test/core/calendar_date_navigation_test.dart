import 'dart:io';

import 'package:duoyi/core/calendar_date_navigation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CalendarDateNavigation', () {
    test('shifts civil days and ignores the input clock', () {
      final late = DateTime(2024, 3, 10, 23, 59, 58, 321, 654);

      _expectCivil(CalendarDateNavigation.tryShiftDays(late, 0), 2024, 3, 10);
      _expectCivil(CalendarDateNavigation.tryShiftDays(late, 1), 2024, 3, 11);
      _expectCivil(CalendarDateNavigation.tryShiftDays(late, -7), 2024, 3, 3);
      _expectCivil(CalendarDateNavigation.tryShiftDays(late, 3), 2024, 3, 13);
    });

    test('uses UTC and local inputs by their civil fields', () {
      final local = DateTime(2024, 2, 28, 23, 59);
      final utc = DateTime.utc(2024, 2, 28, 1, 15);

      _expectCivil(CalendarDateNavigation.tryShiftDays(local, 1), 2024, 2, 29);
      _expectCivil(CalendarDateNavigation.tryShiftDays(utc, 1), 2024, 2, 29);
    });

    test('month shifts clamp to the target month length', () {
      _expectCivil(
        CalendarDateNavigation.tryShiftMonths(DateTime(2024, 1, 31, 18), 1),
        2024,
        2,
        29,
      );
      _expectCivil(
        CalendarDateNavigation.tryShiftMonths(DateTime(2024, 3, 31), -1),
        2024,
        2,
        29,
      );
      _expectCivil(
        CalendarDateNavigation.tryShiftMonths(DateTime(1900, 1, 31), 1),
        1900,
        2,
        28,
      );
    });

    test(
      'year shifts preserve leap days when possible and otherwise clamp',
      () {
        _expectCivil(
          CalendarDateNavigation.tryShiftYears(DateTime(1996, 2, 29), 4),
          2000,
          2,
          29,
        );
        _expectCivil(
          CalendarDateNavigation.tryShiftYears(DateTime(1896, 2, 29), 4),
          1900,
          2,
          28,
        );
        _expectCivil(
          CalendarDateNavigation.tryShiftYears(DateTime(2000, 2, 29), -100),
          1900,
          2,
          28,
        );
      },
    );

    test('keeps valid shifts at both supported year endpoints', () {
      _expectCivil(
        CalendarDateNavigation.tryShiftDays(DateTime(1, 1, 1), 1),
        1,
        1,
        2,
      );
      _expectCivil(
        CalendarDateNavigation.tryShiftDays(DateTime(9999, 12, 31), -1),
        9999,
        12,
        30,
      );
      _expectCivil(
        CalendarDateNavigation.tryShiftMonths(DateTime(1, 1, 31), 1),
        1,
        2,
        28,
      );
      _expectCivil(
        CalendarDateNavigation.tryShiftMonths(DateTime(9999, 12, 31), -1),
        9999,
        11,
        30,
      );
      _expectCivil(
        CalendarDateNavigation.tryShiftYears(DateTime(1, 6, 15), 1),
        2,
        6,
        15,
      );
      _expectCivil(
        CalendarDateNavigation.tryShiftYears(DateTime(9999, 6, 15), -1),
        9998,
        6,
        15,
      );
    });

    test('returns null beyond either endpoint and for huge offsets', () {
      expect(
        CalendarDateNavigation.tryShiftDays(DateTime(1, 1, 1), -1),
        isNull,
      );
      expect(
        CalendarDateNavigation.tryShiftDays(DateTime(9999, 12, 31), 1),
        isNull,
      );
      expect(
        CalendarDateNavigation.tryShiftMonths(DateTime(1, 1, 1), -1),
        isNull,
      );
      expect(
        CalendarDateNavigation.tryShiftMonths(DateTime(9999, 12, 31), 1),
        isNull,
      );
      expect(
        CalendarDateNavigation.tryShiftYears(DateTime(1, 1, 1), -1),
        isNull,
      );
      expect(
        CalendarDateNavigation.tryShiftYears(DateTime(9999, 12, 31), 1),
        isNull,
      );

      const huge = 9223372036854775807;
      final middle = DateTime(5000, 6, 15);
      const smallestOffset = -9223372036854775808;
      for (final offset in [huge, -huge, smallestOffset]) {
        expect(CalendarDateNavigation.tryShiftDays(middle, offset), isNull);
        expect(CalendarDateNavigation.tryShiftMonths(middle, offset), isNull);
        expect(CalendarDateNavigation.tryShiftYears(middle, offset), isNull);
      }
    });

    test('accepts the exact full-range offsets before rejecting one more', () {
      final first = DateTime(1, 1, 1);
      final last = DateTime(9999, 12, 31);
      _expectCivil(
        CalendarDateNavigation.tryShiftDays(first, 3652058),
        9999,
        12,
        31,
      );
      _expectCivil(
        CalendarDateNavigation.tryShiftDays(last, -3652058),
        1,
        1,
        1,
      );
      expect(CalendarDateNavigation.tryShiftDays(first, 3652059), isNull);
      expect(CalendarDateNavigation.tryShiftDays(last, -3652059), isNull);
      _expectCivil(
        CalendarDateNavigation.tryShiftMonths(first, 119987),
        9999,
        12,
        1,
      );
      expect(CalendarDateNavigation.tryShiftMonths(first, 119988), isNull);
      _expectCivil(
        CalendarDateNavigation.tryShiftYears(first, 9998),
        9999,
        1,
        1,
      );
      expect(CalendarDateNavigation.tryShiftYears(first, 9999), isNull);
    });

    test('rejects invalid input years and preserves null list slots', () {
      for (final invalid in [DateTime(0, 6, 15), DateTime(10000, 6, 15)]) {
        expect(CalendarDateNavigation.tryShiftDays(invalid, 0), isNull);
        expect(CalendarDateNavigation.tryShiftMonths(invalid, 0), isNull);
        expect(CalendarDateNavigation.tryShiftYears(invalid, 0), isNull);
        expect(
          CalendarDateNavigation.weekDays(invalid),
          List<DateTime?>.filled(7, null),
        );
        expect(CalendarDateNavigation.daysFrom(invalid, 3), [null, null, null]);
      }
    });

    test('returns Monday through Sunday as seven local civil-day slots', () {
      final week = CalendarDateNavigation.weekDays(DateTime(2024, 2, 29, 21));

      _expectCivilSequence(week, [
        [2024, 2, 26],
        [2024, 2, 27],
        [2024, 2, 28],
        [2024, 2, 29],
        [2024, 3, 1],
        [2024, 3, 2],
        [2024, 3, 3],
      ]);
    });

    test('keeps fixed week slots at years 0001 and 9999', () {
      _expectCivilSequence(CalendarDateNavigation.weekDays(DateTime(1, 1, 1)), [
        [1, 1, 1],
        [1, 1, 2],
        [1, 1, 3],
        [1, 1, 4],
        [1, 1, 5],
        [1, 1, 6],
        [1, 1, 7],
      ]);
      _expectCivilSequence(
        CalendarDateNavigation.weekDays(DateTime(9999, 12, 31)),
        [
          [9999, 12, 27],
          [9999, 12, 28],
          [9999, 12, 29],
          [9999, 12, 30],
          [9999, 12, 31],
          null,
          null,
        ],
      );
    });

    test('daysFrom includes its start and retains range-edge slots', () {
      _expectCivilSequence(
        CalendarDateNavigation.daysFrom(DateTime(2023, 12, 31, 23, 40), 4),
        [
          [2023, 12, 31],
          [2024, 1, 1],
          [2024, 1, 2],
          [2024, 1, 3],
        ],
      );
      _expectCivilSequence(
        CalendarDateNavigation.daysFrom(DateTime(9999, 12, 30), 3),
        [
          [9999, 12, 30],
          [9999, 12, 31],
          null,
        ],
      );
      expect(CalendarDateNavigation.daysFrom(DateTime(2024, 1, 1), 0), isEmpty);
      expect(
        () => CalendarDateNavigation.daysFrom(DateTime(2024, 1, 1), -1),
        throwsA(isA<RangeError>()),
      );
    });

    if (Platform.environment['DUOYI_REQUIRE_DST'] == '1') {
      test(
        'preserves civil sequences across both local DST transitions when required',
        () {
          final transitions = _localOffsetTransitions2024();
          final starts = transitions
              .where((transition) => transition.offsetChangeMinutes > 0)
              .toList();
          final ends = transitions
              .where((transition) => transition.offsetChangeMinutes < 0)
              .toList();

          expect(starts, isNotEmpty, reason: 'Expected a local DST start');
          expect(ends, isNotEmpty, reason: 'Expected a local DST end');

          for (final transition in [starts.first, ends.first]) {
            final day = transition.day;
            final priorNoon = DateTime(day.year, day.month, day.day - 1, 12);
            expect(day.timeZoneOffset, isNot(priorNoon.timeZoneOffset));

            final priorLate = DateTime(
              day.year,
              day.month,
              day.day - 1,
              23,
              59,
            );
            _expectCivil(
              CalendarDateNavigation.tryShiftDays(priorLate, 1),
              day.year,
              day.month,
              day.day,
            );
            _expectCivilSequence(
              CalendarDateNavigation.daysFrom(priorLate, 3),
              [
                [priorLate.year, priorLate.month, priorLate.day],
                [day.year, day.month, day.day],
                _dateParts(
                  DateTime.utc(
                    day.year,
                    day.month,
                    day.day,
                  ).add(const Duration(days: 1)),
                ),
              ],
            );

            final week = CalendarDateNavigation.weekDays(day);
            final actualDays = week.whereType<DateTime>().toList();
            expect(actualDays, hasLength(7));
            _expectContinuous(actualDays);
          }
        },
      );
    }

    if (Platform.environment['DUOYI_REQUIRE_APIA'] == '1') {
      test(
        'returns null for the Apia skipped day without duplicating its neighbor',
        () {
          final normalized = DateTime(2011, 12, 30, 12);
          expect(
            [normalized.year, normalized.month, normalized.day],
            [2011, 12, 31],
          );
          expect(
            CalendarDateNavigation.tryShiftDays(
              DateTime(2011, 12, 29, 23, 59),
              1,
            ),
            isNull,
          );
          expect(
            CalendarDateNavigation.tryShiftDays(DateTime(2011, 12, 31), -1),
            isNull,
          );
          expect(
            CalendarDateNavigation.tryShiftDays(DateTime.utc(2011, 12, 30), 0),
            isNull,
          );
          expect(
            CalendarDateNavigation.tryShiftMonths(DateTime(2011, 11, 30), 1),
            isNull,
          );
          expect(
            CalendarDateNavigation.tryShiftYears(DateTime(2010, 12, 30), 1),
            isNull,
          );

          final week = CalendarDateNavigation.weekDays(DateTime(2011, 12, 28));
          _expectCivilSequence(week, [
            [2011, 12, 26],
            [2011, 12, 27],
            [2011, 12, 28],
            [2011, 12, 29],
            null,
            [2011, 12, 31],
            [2012, 1, 1],
          ]);
          _expectCivilSequence(
            CalendarDateNavigation.daysFrom(DateTime(2011, 12, 29, 22), 3),
            [
              [2011, 12, 29],
              null,
              [2011, 12, 31],
            ],
          );
        },
      );
    }
  });
}

void _expectCivil(DateTime? actual, int year, int month, int day) {
  expect(actual, isNotNull);
  final value = actual!;
  expect(value.isUtc, isFalse, reason: 'Results should be local dates');
  expect([value.year, value.month, value.day], [year, month, day]);
  expect(
    [
      value.hour,
      value.minute,
      value.second,
      value.millisecond,
      value.microsecond,
    ],
    [0, 0, 0, 0, 0],
    reason: 'The input clock should not be carried into the result',
  );
}

void _expectCivilSequence(List<DateTime?> actual, List<List<int>?> expected) {
  expect(actual, hasLength(expected.length));
  for (var index = 0; index < expected.length; index++) {
    final expectedDate = expected[index];
    if (expectedDate == null) {
      expect(actual[index], isNull, reason: 'slot $index should stay empty');
    } else {
      _expectCivil(
        actual[index],
        expectedDate[0],
        expectedDate[1],
        expectedDate[2],
      );
    }
  }
}

List<({DateTime day, int offsetChangeMinutes})> _localOffsetTransitions2024() {
  final transitions = <({DateTime day, int offsetChangeMinutes})>[];
  var prior = DateTime(2024, 1, 1, 12);
  for (var dayOfYear = 2; dayOfYear <= 366; dayOfYear++) {
    final current = DateTime(2024, 1, dayOfYear, 12);
    final change =
        current.timeZoneOffset.inMinutes - prior.timeZoneOffset.inMinutes;
    if (change != 0) {
      transitions.add((day: current, offsetChangeMinutes: change));
    }
    prior = current;
  }
  return transitions;
}

List<int> _dateParts(DateTime date) => [date.year, date.month, date.day];

void _expectContinuous(List<DateTime> dates) {
  final keys = dates
      .map((date) => '${date.year}-${date.month}-${date.day}')
      .toSet();
  expect(keys, hasLength(dates.length), reason: 'Dates must not repeat');
  for (var index = 1; index < dates.length; index++) {
    final prior = dates[index - 1];
    final current = dates[index];
    final priorOrdinal = DateTime.utc(prior.year, prior.month, prior.day);
    final currentOrdinal = DateTime.utc(
      current.year,
      current.month,
      current.day,
    );
    expect(currentOrdinal.difference(priorOrdinal), const Duration(days: 1));
  }
}
