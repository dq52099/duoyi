import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:duoyi/models/calendar_event.dart';
import 'package:duoyi/providers/calendar_provider.dart';

String _testDateKey(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

Set<String> _indexedDateKeys(CalendarProvider provider) =>
    provider.datesWithEvents.map(_testDateKey).toSet();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'timed spans index every civil date across spring and fall DST changes',
    () {
      final springStart = DateTime(2026, 3, 7, 10);
      final springEnd = DateTime(2026, 3, 10, 12);
      final fallStart = DateTime(2026, 10, 31, 10);
      final fallEnd = DateTime(2026, 11, 3, 12);

      if (Platform.environment['DUOYI_REQUIRE_DST'] == '1') {
        expect(springStart.timeZoneOffset, isNot(springEnd.timeZoneOffset));
        expect(fallStart.timeZoneOffset, isNot(fallEnd.timeZoneOffset));
      }

      final springTodo = CalendarEvent(
        id: 'civil-span-spring-todo',
        title: 'Spring project span',
        date: springStart,
        endDate: springEnd,
        type: CalendarEventType.todo,
        color: Colors.orange,
        projectId: 'work',
        workspaceId: 'workspace-a',
      );
      final springTimeEntry = CalendarEvent(
        id: 'civil-span-spring-time',
        title: 'Spring time entry',
        date: springStart,
        endDate: springEnd,
        type: CalendarEventType.timeEntry,
        color: Colors.blue,
        workspaceId: 'workspace-a',
      );
      final springOtherWorkspace = CalendarEvent(
        id: 'civil-span-spring-other-workspace',
        title: 'Other workspace span',
        date: springStart,
        endDate: springEnd,
        type: CalendarEventType.event,
        color: Colors.green,
        workspaceId: 'workspace-b',
      );
      final fallTimeEntry = CalendarEvent(
        id: 'civil-span-fall-time',
        title: 'Fall time entry',
        date: fallStart,
        endDate: fallEnd,
        type: CalendarEventType.timeEntry,
        color: Colors.blue,
        workspaceId: 'workspace-a',
      );
      final events = [
        springTodo,
        springTimeEntry,
        springOtherWorkspace,
        fallTimeEntry,
      ];
      final provider = CalendarProvider();
      addTearDown(provider.dispose);
      provider.setExternalEvents(events);
      provider.rebuild(const [], const [], const [], const ColorScheme.light());

      const springKeys = [
        '2026-03-07',
        '2026-03-08',
        '2026-03-09',
        '2026-03-10',
      ];
      const fallKeys = ['2026-10-31', '2026-11-01', '2026-11-02', '2026-11-03'];
      final allExpectedKeys = {...springKeys, ...fallKeys};
      expect(_indexedDateKeys(provider), allExpectedKeys);

      for (final key in springKeys) {
        final date = DateTime.parse(key);
        expect(
          provider.getEventsForDate(date),
          containsAll([springTodo, springTimeEntry, springOtherWorkspace]),
          reason: 'all three spring events cover $key',
        );
        expect(provider.dateEventTypes[key]?.toSet(), {
          CalendarEventType.todo,
          CalendarEventType.timeEntry,
          CalendarEventType.event,
        });
        expect(provider.filteredDateEventCounts(null)[key], 3);
        expect(
          provider.getEventsForDate(
            date,
            activeTypes: {CalendarEventType.todo},
            projectKey: 'work',
            workspaceId: 'workspace-a',
          ),
          [springTodo],
        );
        expect(
          provider.getEventsForDate(
            date,
            activeTypes: {CalendarEventType.timeEntry},
            workspaceId: 'workspace-a',
          ),
          [springTimeEntry],
        );
        expect(provider.getEventsForDate(date, projectKey: 'work'), [
          springTodo,
        ]);
        expect(provider.getEventsForDate(date, workspaceId: 'workspace-b'), [
          springOtherWorkspace,
        ]);
        expect(
          provider.filteredDateEventTypes(
            {CalendarEventType.todo},
            projectKey: 'work',
            workspaceId: 'workspace-a',
          )[key],
          [CalendarEventType.todo],
        );
        expect(
          provider.filteredDateEventCounts(
            {CalendarEventType.todo},
            projectKey: 'work',
            workspaceId: 'workspace-a',
          )[key],
          1,
        );
      }

      for (final key in fallKeys) {
        final date = DateTime.parse(key);
        expect(provider.getEventsForDate(date), [fallTimeEntry]);
        expect(provider.dateEventTypes[key], [CalendarEventType.timeEntry]);
        expect(provider.filteredDateEventCounts(null)[key], 1);
      }
      expect(
        provider.getEventsForDate(DateTime(2026, 3, 11)),
        isNot(contains(springTodo)),
      );
      expect(
        provider.getEventsForDate(DateTime(2026, 11, 4)),
        isNot(contains(fallTimeEntry)),
      );
    },
  );

  test(
    'midnight-exclusive spans end on the preceding civil date across DST',
    () {
      final springStart = DateTime(2026, 3, 7, 10);
      final springExclusiveEnd = DateTime(2026, 3, 10);
      final fallStart = DateTime(2026, 10, 31, 10);
      final fallExclusiveEnd = DateTime(2026, 11, 3);

      if (Platform.environment['DUOYI_REQUIRE_DST'] == '1') {
        expect(
          springStart.timeZoneOffset,
          isNot(springExclusiveEnd.timeZoneOffset),
        );
        expect(
          fallStart.timeZoneOffset,
          isNot(fallExclusiveEnd.timeZoneOffset),
        );
      }

      final springEvent = CalendarEvent(
        id: 'exclusive-spring-span',
        title: 'Spring exclusive end',
        date: springStart,
        endDate: springExclusiveEnd,
        type: CalendarEventType.timeEntry,
        color: Colors.blue,
      );
      final fallEvent = CalendarEvent(
        id: 'exclusive-fall-span',
        title: 'Fall exclusive end',
        date: fallStart,
        endDate: fallExclusiveEnd,
        type: CalendarEventType.timeEntry,
        color: Colors.green,
      );
      final provider = CalendarProvider();
      addTearDown(provider.dispose);
      provider.setExternalEvents([springEvent, fallEvent]);
      provider.rebuild(const [], const [], const [], const ColorScheme.light());

      const springKeys = ['2026-03-07', '2026-03-08', '2026-03-09'];
      const fallKeys = ['2026-10-31', '2026-11-01', '2026-11-02'];
      final allExpectedKeys = {...springKeys, ...fallKeys};
      expect(_indexedDateKeys(provider), allExpectedKeys);

      for (final key in springKeys) {
        expect(provider.getEventsForDate(DateTime.parse(key)), [springEvent]);
        expect(provider.dateEventTypes[key], [CalendarEventType.timeEntry]);
        expect(provider.filteredDateEventCounts(null)[key], 1);
      }
      for (final key in fallKeys) {
        expect(provider.getEventsForDate(DateTime.parse(key)), [fallEvent]);
        expect(provider.dateEventTypes[key], [CalendarEventType.timeEntry]);
        expect(provider.filteredDateEventCounts(null)[key], 1);
      }
      expect(provider.getEventsForDate(springExclusiveEnd), isEmpty);
      expect(provider.getEventsForDate(fallExclusiveEnd), isEmpty);
    },
  );

  if (Platform.environment['DUOYI_REQUIRE_APIA'] == '1') {
    test('Apia skipped civil day has no phantom or duplicate indexed date', () {
      final skippedDayConstruction = DateTime(2011, 12, 30);
      final skippedDayWasNormalized =
          skippedDayConstruction.year != 2011 ||
          skippedDayConstruction.month != 12 ||
          skippedDayConstruction.day != 30;
      expect(
        skippedDayWasNormalized,
        isTrue,
        reason:
            'DUOYI_REQUIRE_APIA requires the host timezone to skip 2011-12-30',
      );

      final timed = CalendarEvent(
        id: 'apia-timed-span',
        title: 'Timed span around skipped day',
        date: DateTime(2011, 12, 29, 10),
        endDate: DateTime(2011, 12, 31, 12),
        type: CalendarEventType.timeEntry,
        color: Colors.blue,
      );
      final exclusive = CalendarEvent(
        id: 'apia-exclusive-span',
        title: 'Exclusive span around skipped day',
        date: DateTime(2011, 12, 29, 14),
        endDate: DateTime(2012, 1, 1),
        type: CalendarEventType.timeEntry,
        color: Colors.green,
      );
      final exclusiveAtGap = CalendarEvent(
        id: 'apia-exclusive-end-after-gap',
        title: 'Midnight after the skipped day',
        date: DateTime(2011, 12, 29, 14),
        endDate: DateTime(2011, 12, 31),
        type: CalendarEventType.timeEntry,
        color: Colors.orange,
      );
      final provider = CalendarProvider();
      addTearDown(provider.dispose);
      provider.setExternalEvents([timed, exclusive, exclusiveAtGap]);
      provider.rebuild(const [], const [], const [], const ColorScheme.light());

      const expectedKeys = {'2011-12-29', '2011-12-31'};
      expect(_indexedDateKeys(provider), expectedKeys);
      expect(provider.dateEventTypes.keys.toSet(), expectedKeys);
      expect(provider.filteredDateEventCounts(null), {
        '2011-12-29': 3,
        '2011-12-31': 2,
      });
      expect(provider.getEventsForDate(DateTime.utc(2011, 12, 29)), [
        timed,
        exclusive,
        exclusiveAtGap,
      ]);
      expect(provider.getEventsForDate(DateTime.utc(2011, 12, 31)), [
        timed,
        exclusive,
      ]);
      expect(
        provider.getEventsForDate(DateTime.utc(2011, 12, 30)),
        isEmpty,
        reason:
            'UTC fields query the skipped civil key without local normalization',
      );
      expect(
        provider.getEventsForDate(DateTime.utc(2012, 1, 1)),
        isEmpty,
        reason: 'the exclusive Jan 1 end is not indexed',
      );
    });
  }

  test(
    'single-day event keys retain the provider year-padding contract at 1 and 9999',
    () {
      final first = CalendarEvent(
        id: 'calendar-year-one',
        title: 'First supported year',
        date: DateTime(1, 1, 1),
        type: CalendarEventType.event,
        color: Colors.orange,
      );
      final last = CalendarEvent(
        id: 'calendar-year-nine-nine-nine-nine',
        title: 'Last four-digit year',
        date: DateTime(9999, 12, 31),
        type: CalendarEventType.event,
        color: Colors.blue,
      );
      final provider = CalendarProvider();
      addTearDown(provider.dispose);
      provider.setExternalEvents([first, last]);
      provider.rebuild(const [], const [], const [], const ColorScheme.light());

      expect(first.dateKey, '1-01-01');
      expect(last.dateKey, '9999-12-31');
      expect(_indexedDateKeys(provider), {'1-01-01', '9999-12-31'});
      expect(provider.dateEventTypes.keys.toSet(), {'1-01-01', '9999-12-31'});
      expect(provider.filteredDateEventCounts(null), {
        '1-01-01': 1,
        '9999-12-31': 1,
      });
      expect(provider.getEventsForDate(DateTime(1, 1, 1)), [first]);
      expect(provider.getEventsForDate(DateTime(9999, 12, 31)), [last]);
    },
  );
}
