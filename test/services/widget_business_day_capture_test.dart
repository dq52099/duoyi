import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:duoyi/core/calendar_aggregator.dart';
import 'package:duoyi/models/anniversary.dart';
import 'package:duoyi/models/calendar_event.dart';
import 'package:duoyi/models/countdown.dart';
import 'package:duoyi/models/pomodoro.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/calendar_provider.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'focus sessions are captured for explicit historical and future days',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final provider = PomodoroProvider();
      addTearDown(provider.dispose);

      final overnightFocus = _session(
        id: 'started-before-history-day',
        start: DateTime(2020, 2, 28, 23, 40),
        end: DateTime(2020, 2, 29, 0, 10),
        type: PomodoroType.focus,
      );
      final historicalMidnightFocus = _session(
        id: 'historical-midnight-focus',
        start: DateTime.utc(2020, 2, 29),
        end: DateTime.utc(2020, 2, 29, 0, 25),
        type: PomodoroType.focus,
      );
      final historicalDaytimeFocus = _session(
        id: 'historical-daytime-focus',
        start: DateTime(2020, 2, 29, 14),
        end: DateTime(2020, 2, 29, 14, 25),
        type: PomodoroType.focus,
      );
      final historicalBreak = _session(
        id: 'historical-break',
        start: DateTime(2020, 2, 29, 15),
        end: DateTime(2020, 2, 29, 15, 5),
        type: PomodoroType.shortBreak,
      );
      final futureFocus = _session(
        id: 'future-focus',
        start: DateTime(2042, 10, 5),
        end: DateTime(2042, 10, 5, 0, 25),
        type: PomodoroType.focus,
      );
      final sessions = [
        overnightFocus,
        historicalMidnightFocus,
        historicalBreak,
        historicalDaytimeFocus,
        futureFocus,
      ];
      await provider.debugAddSessionsForTest(sessions);

      final sessionsList = provider.sessions;
      final sessionsBefore = List<PomodoroSession>.of(sessionsList);
      final stateBefore = provider.state;
      final countTodayBefore = provider.sessionCountToday;
      var notifications = 0;
      provider.addListener(() => notifications++);

      withClock(Clock.fixed(DateTime(2030, 6, 15, 12)), () {
        _expectSessionIdentityOrder(
          provider.focusSessionsForDate(DateTime(2020, 2, 29, 23, 50)),
          [historicalMidnightFocus, historicalDaytimeFocus],
        );
        _expectSessionIdentityOrder(
          provider.focusSessionsForDate(DateTime.utc(2020, 2, 29, 2)),
          [historicalMidnightFocus, historicalDaytimeFocus],
        );
        _expectSessionIdentityOrder(
          provider.focusSessionsForDate(DateTime.utc(2042, 10, 5, 23)),
          [futureFocus],
        );
      });

      expect(identical(provider.sessions, sessionsList), isTrue);
      expect(provider.sessions, hasLength(sessionsBefore.length));
      for (var index = 0; index < sessionsBefore.length; index++) {
        expect(
          identical(provider.sessions[index], sessionsBefore[index]),
          isTrue,
        );
      }
      expect(identical(provider.state, stateBefore), isTrue);
      expect(provider.sessionCountToday, countTodayBefore);
      expect(notifications, 0);
    },
  );

  test(
    'anniversary calculations and provider sorting use the captured day',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final provider = AnniversaryProvider();
      addTearDown(provider.dispose);

      final farAnnual = Anniversary(
        id: 'unpinned-far',
        title: 'Far annual date',
        originDate: DateTime(1999, 1, 15, 7, 20),
        type: AnniversaryType.memorial,
      );
      final pinnedNear = Anniversary(
        id: 'pinned-near',
        title: 'Pinned upcoming birthday',
        originDate: DateTime(2000, 1, 12, 8, 45),
        type: AnniversaryType.birthday,
        isPinned: true,
      );
      final todayAnnual = Anniversary(
        id: 'unpinned-today',
        title: 'Today birthday',
        originDate: DateTime(2000, 1, 10, 9, 15),
        type: AnniversaryType.birthday,
      );
      final normalOrigin = DateTime(2025, 1, 8, 18, 30);
      final pinnedPast = Anniversary(
        id: 'pinned-past-once',
        title: 'Pinned past single date',
        originDate: normalOrigin,
        type: AnniversaryType.normal,
        isPinned: true,
      );
      final items = [farAnnual, pinnedNear, todayAnnual, pinnedPast];
      for (final item in items) {
        await provider.add(item);
      }
      final originalDateJson = {
        for (final item in items) item.id: item.toJson()['originDate'],
      };
      final originalDates = {
        for (final item in items) item.id: item.originDate,
      };
      final asOf = DateTime(2025, 1, 10, 23, 55);
      final storedBefore = {
        for (final item in provider.itemsAt(asOf)) item.id: item.toJson(),
      };

      late List<Anniversary> sortedAt;
      withClock(Clock.fixed(DateTime(2040, 7, 1)), () {
        expect(pinnedPast.nextOccurrenceForDate(asOf), same(normalOrigin));
        expect(pinnedPast.daysRemainingForDate(asOf), -2);
        expect(pinnedPast.yearsPassedForDate(asOf), isNull);

        expect(pinnedNear.nextOccurrenceForDate(asOf), DateTime(2025, 1, 12));
        expect(pinnedNear.daysRemainingForDate(asOf), 2);
        expect(pinnedNear.yearsPassedForDate(asOf), 24);
        expect(todayAnnual.nextOccurrenceForDate(asOf), DateTime(2025, 1, 10));
        expect(todayAnnual.daysRemainingForDate(asOf), 0);
        expect(todayAnnual.yearsPassedForDate(asOf), 25);
        expect(farAnnual.nextOccurrenceForDate(asOf), DateTime(2025, 1, 15));
        expect(farAnnual.daysRemainingForDate(asOf), 5);
        expect(farAnnual.yearsPassedForDate(asOf), 25);

        sortedAt = provider.itemsAt(asOf);
      });

      expect(sortedAt.map((item) => item.id), [
        'pinned-past-once',
        'pinned-near',
        'unpinned-today',
        'unpinned-far',
      ]);
      final expectedItems = [pinnedPast, pinnedNear, todayAnnual, farAnnual];
      for (var index = 0; index < expectedItems.length; index++) {
        expect(sortedAt[index].toJson(), storedBefore[expectedItems[index].id]);
        expect(identical(sortedAt[index], expectedItems[index]), isFalse);
      }
      expect({
        for (final item in provider.itemsAt(asOf)) item.id: item.toJson(),
      }, storedBefore);
      for (final item in items) {
        expect(item.originDate, originalDates[item.id]);
        expect(item.toJson()['originDate'], originalDateJson[item.id]);
      }
    },
  );

  test(
    'countdown days use signed UTC civil-day differences, independent of clock',
    () {
      final future = CountdownItem(
        id: 'future-countdown',
        title: 'Future target',
        targetDate: DateTime.utc(2024, 6, 12, 23, 45),
      );
      final past = CountdownItem(
        id: 'past-countdown',
        title: 'Past target',
        targetDate: DateTime(2024, 6, 8, 7, 30),
      );
      final sameDay = CountdownItem(
        id: 'same-day-countdown',
        title: 'Same civil day',
        targetDate: DateTime.utc(2024, 6, 10, 23, 59),
      );
      final futureDateJson = future.toJson()['targetDate'];

      withClock(Clock.fixed(DateTime(2040, 6, 1, 12)), () {
        expect(future.daysRemainingForDate(DateTime(2024, 6, 10, 23, 55)), 2);
        expect(past.daysRemainingForDate(DateTime.utc(2024, 6, 10, 1)), -2);
        expect(sameDay.daysRemainingForDate(DateTime(2024, 6, 10, 0)), 0);
      });
      expect(future.toJson()['targetDate'], futureDateJson);
    },
  );

  test(
    'aggregator and provider snapshots pass as-of and retain generated metadata',
    () {
      final asOf = DateTime(2025, 1, 10, 23, 55);
      final birthday = Anniversary(
        id: 'snapshot-birthday',
        title: 'Snapshot birthday',
        originDate: DateTime(2000, 1, 12),
        type: AnniversaryType.birthday,
      );
      final countdown = CountdownItem(
        id: 'snapshot-launch',
        title: 'Snapshot launch',
        targetDate: DateTime(2025, 1, 12),
      );
      final aggregatorEvents = CalendarAggregator.buildEvents(
        todos: const [],
        habits: const [],
        pomodoroSessions: const [],
        colorScheme: const ColorScheme.light(),
        anniversaries: [birthday],
        countdowns: [countdown],
        now: asOf,
      );

      final provider = CalendarProvider();
      addTearDown(provider.dispose);
      final snapshot = provider.buildEventsForDateSnapshot(
        DateTime.utc(2025, 1, 12, 8),
        const [],
        const [],
        const [],
        const ColorScheme.light(),
        anniversaries: [birthday],
        countdowns: [countdown],
        now: asOf,
      );

      final expectedIds = [
        'anniversary_snapshot-birthday',
        'countdown_snapshot-launch',
      ];
      expect(aggregatorEvents.map((event) => event.id), expectedIds);
      expect(snapshot.map((event) => event.id), expectedIds);
      final directBirthday = aggregatorEvents.first;
      final snapshotBirthday = snapshot.first;
      expect(directBirthday.date, DateTime(2025, 1, 12));
      expect(snapshotBirthday.date, DateTime(2025, 1, 12));
      expect(directBirthday.displayMetadata, isA<AnniversaryDisplayMetadata>());
      expect(
        snapshotBirthday.displayMetadata,
        isA<AnniversaryDisplayMetadata>(),
      );
      final birthdayMetadata =
          snapshotBirthday.displayMetadata! as AnniversaryDisplayMetadata;
      expect(birthdayMetadata.daysRemaining, 2);
      expect(birthdayMetadata.yearsPassed, 24);

      final directCountdown = aggregatorEvents.last;
      final snapshotCountdown = snapshot.last;
      expect(directCountdown.displayMetadata, isA<CountdownDisplayMetadata>());
      expect(
        snapshotCountdown.displayMetadata,
        isA<CountdownDisplayMetadata>(),
      );
      expect(
        (snapshotCountdown.displayMetadata! as CountdownDisplayMetadata)
            .daysRemaining,
        2,
      );
    },
  );

  if (Platform.environment['DUOYI_REQUIRE_DST'] == '1') {
    test('New York spring and autumn day counts follow civil dates', () {
      final springAsOf = DateTime(2026, 3, 8);
      final springTarget = DateTime(2026, 3, 9);
      expect(springAsOf.timeZoneOffset, isNot(springTarget.timeZoneOffset));
      expect(DateTime(2026, 3, 9).difference(DateTime(2026, 3, 8)).inHours, 23);

      final autumnAsOf = DateTime(2026, 11, 1);
      final autumnTarget = DateTime(2026, 11, 2);
      expect(autumnAsOf.timeZoneOffset, isNot(autumnTarget.timeZoneOffset));
      expect(
        DateTime(2026, 11, 2).difference(DateTime(2026, 11, 1)).inHours,
        25,
      );

      for (final (asOf, target) in [
        (DateTime(2026, 3, 8, 23, 45), DateTime(2026, 3, 9)),
        (DateTime(2026, 11, 1, 23, 45), DateTime(2026, 11, 2)),
      ]) {
        final countdown = CountdownItem(
          id: 'dst-${target.month}',
          title: 'DST target',
          targetDate: target,
        );
        final anniversary = Anniversary(
          id: 'dst-anniversary-${target.month}',
          title: 'DST anniversary',
          originDate: target,
          type: AnniversaryType.normal,
        );
        expect(countdown.daysRemainingForDate(asOf), 1);
        expect(anniversary.daysRemainingForDate(asOf), 1);
      }
    });
  }

  if (Platform.environment['DUOYI_REQUIRE_APIA'] == '1') {
    test('Apia date calculations bridge the skipped civil day by two days', () {
      final skippedLocal = DateTime(2011, 12, 30);
      expect(
        [skippedLocal.year, skippedLocal.month, skippedLocal.day],
        [2011, 12, 31],
        reason: 'DUOYI_REQUIRE_APIA requires 2011-12-30 to be skipped locally',
      );

      final before = DateTime(2011, 12, 29, 18);
      final after = DateTime(2011, 12, 31, 8);
      final forwardCountdown = CountdownItem(
        id: 'apia-forward',
        title: 'After the skipped day',
        targetDate: after,
      );
      final backwardCountdown = CountdownItem(
        id: 'apia-backward',
        title: 'Before the skipped day',
        targetDate: before,
      );
      final forwardAnniversary = Anniversary(
        id: 'apia-anniversary-forward',
        title: 'After the skipped day',
        originDate: after,
        type: AnniversaryType.normal,
      );

      expect(forwardCountdown.daysRemainingForDate(before), 2);
      expect(backwardCountdown.daysRemainingForDate(after), -2);
      expect(forwardAnniversary.daysRemainingForDate(before), 2);
    });
  }
}

PomodoroSession _session({
  required String id,
  required DateTime start,
  required DateTime end,
  required PomodoroType type,
}) => PomodoroSession(
  id: id,
  startTime: start,
  endTime: end,
  durationSeconds: 25 * 60,
  type: type,
);

void _expectSessionIdentityOrder(
  List<PomodoroSession> actual,
  List<PomodoroSession> expected,
) {
  expect(actual, hasLength(expected.length));
  for (var index = 0; index < expected.length; index++) {
    expect(identical(actual[index], expected[index]), isTrue);
  }
}
