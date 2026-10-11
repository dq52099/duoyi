import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:duoyi/models/calendar_event.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/calendar_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'get reads rebuilt events while snapshots include generated, local, and external sources in order',
    () async {
      SharedPreferences.setMockInitialValues({});
      final provider = CalendarProvider();
      addTearDown(provider.dispose);

      final todo = TodoItem(
        id: 'generated-span',
        title: 'Generated multi-day task',
        date: DateTime(2024, 6, 10, 9),
        dueDate: DateTime(2024, 6, 12, 17),
        listGroupId: 'work',
        workspaceId: 'workspace-a',
      );
      final localInput = CalendarEvent(
        id: 'local-span',
        title: 'Local multi-day event',
        date: DateTime(2024, 6, 10, 11),
        endDate: DateTime(2024, 6, 12, 11),
        type: CalendarEventType.event,
        color: Colors.green,
        workspaceId: 'workspace-a',
      );
      await provider.addLocalEvent(localInput);
      final storedLocal = provider.localEvents.single;

      final externalTodo = CalendarEvent(
        id: 'external-work-todo',
        title: 'External work task',
        date: DateTime(2024, 6, 10, 8),
        endDate: DateTime(2024, 6, 11, 15),
        type: CalendarEventType.todo,
        color: Colors.orange,
        projectId: 'work',
        workspaceId: 'workspace-a',
      );
      final externalOther = CalendarEvent(
        id: 'external-other-workspace',
        title: 'Other workspace event',
        date: DateTime(2024, 6, 11, 10),
        type: CalendarEventType.event,
        color: Colors.blue,
        workspaceId: 'workspace-b',
      );
      provider.setExternalEvents([externalTodo, externalOther]);

      final localQuery = DateTime(2024, 6, 11, 23, 45);
      final utcQuery = DateTime.utc(2024, 6, 11, 2, 30);
      expect(provider.getEventsForDate(localQuery), isEmpty);
      expect(provider.getEventsForDate(utcQuery), isEmpty);

      final unrebuiltSnapshot = _snapshot(provider, utcQuery, todos: [todo]);
      expect(_ids(unrebuiltSnapshot), [
        'todo_generated-span',
        'local-span',
        'external-work-todo',
        'external-other-workspace',
      ]);
      expect(unrebuiltSnapshot[1], same(storedLocal));
      expect(unrebuiltSnapshot[2], same(externalTodo));
      expect(unrebuiltSnapshot[3], same(externalOther));

      provider.rebuild([todo], const [], const [], const ColorScheme.light());
      final generatedCurrent = provider.events.singleWhere(
        (event) => event.id == 'todo_generated-span',
      );
      final current = provider.getEventsForDate(localQuery);
      final expectedCurrent = [
        generatedCurrent,
        storedLocal,
        externalTodo,
        externalOther,
      ];
      _expectIdentityOrder(current, expectedCurrent);
      _expectIdentityOrder(
        provider.getEventsForDate(utcQuery),
        expectedCurrent,
      );
      expect(
        provider.getEventsForDate(
          localQuery,
          activeTypes: {CalendarEventType.todo},
          projectKey: 'work',
          workspaceId: 'workspace-a',
        ),
        [generatedCurrent, externalTodo],
      );
      expect(
        provider.getEventsForDate(
          localQuery,
          activeTypes: {CalendarEventType.event},
          workspaceId: 'workspace-a',
        ),
        [storedLocal],
      );
      expect(provider.getEventsForDate(localQuery, projectKey: 'work'), [
        generatedCurrent,
        externalTodo,
      ]);

      final replacementExternal = externalTodo.copyWith(
        title: 'Updated external work task',
      );
      provider.setExternalEvents([replacementExternal]);
      final refreshedSnapshot = _snapshot(provider, localQuery, todos: [todo]);
      _expectIdentityOrder(refreshedSnapshot, [
        refreshedSnapshot.first,
        storedLocal,
        replacementExternal,
      ]);
      expect(refreshedSnapshot.first.id, 'todo_generated-span');
      expect(
        provider.getEventsForDate(localQuery),
        expectedCurrent,
        reason: 'get reads the current rebuilt collection until rebuild runs',
      );

      provider.rebuild([todo], const [], const [], const ColorScheme.light());
      final refreshedCurrent = provider.getEventsForDate(localQuery);
      expect(_ids(refreshedCurrent), [
        'todo_generated-span',
        'local-span',
        'external-work-todo',
      ]);
      expect(refreshedCurrent[1], same(storedLocal));
      expect(refreshedCurrent[2], same(replacementExternal));
    },
  );

  test(
    'get and snapshot preserve inclusive timed spans and raw end-date rules',
    () {
      final provider = CalendarProvider();
      addTearDown(provider.dispose);
      final timedSpan = CalendarEvent(
        id: 'timed-span',
        title: 'Timed inclusive span',
        date: DateTime(2024, 7, 10, 17, 30),
        endDate: DateTime(2024, 7, 12, 9, 15),
        type: CalendarEventType.timeEntry,
        color: Colors.blue,
      );
      final midnightExclusive = CalendarEvent(
        id: 'midnight-exclusive',
        title: 'Exclusive midnight endpoint',
        date: DateTime(2024, 7, 11, 18),
        endDate: DateTime(2024, 7, 13),
        type: CalendarEventType.event,
        color: Colors.green,
      );
      final endBeforeStart = CalendarEvent(
        id: 'end-before-start',
        title: 'Raw end precedes start',
        date: DateTime(2024, 7, 11, 20),
        endDate: DateTime(2024, 7, 11),
        type: CalendarEventType.event,
        color: Colors.orange,
      );
      final events = [timedSpan, midnightExclusive, endBeforeStart];
      provider.setExternalEvents(events);
      provider.rebuild(const [], const [], const [], const ColorScheme.light());

      final expectedByDay = <int, List<CalendarEvent>>{
        10: [timedSpan],
        11: [timedSpan, midnightExclusive, endBeforeStart],
        12: [timedSpan, midnightExclusive],
        13: [],
      };
      for (final entry in expectedByDay.entries) {
        final localQuery = DateTime(2024, 7, entry.key, 23, 59, 30);
        final utcQuery = DateTime.utc(2024, 7, entry.key, 1, 10);
        _expectIdentityOrder(
          provider.getEventsForDate(localQuery),
          entry.value,
        );
        _expectIdentityOrder(provider.getEventsForDate(utcQuery), entry.value);
        _expectIdentityOrder(_snapshot(provider, localQuery), entry.value);
        _expectIdentityOrder(_snapshot(provider, utcQuery), entry.value);
      }
    },
  );

  test(
    'mixed UTC/local raw end rules match the existing date-count enumeration',
    () {
      final provider = CalendarProvider();
      addTearDown(provider.dispose);
      final mixedZoneFallback = CalendarEvent(
        id: 'mixed-zone-raw-fallback',
        title: 'Mixed UTC and local endpoint',
        date: DateTime.utc(2024, 8, 9, 23),
        endDate: DateTime(2024, 8, 9),
        type: CalendarEventType.timeEntry,
        color: Colors.blue,
      );
      provider.setExternalEvents([mixedZoneFallback]);
      provider.rebuild(const [], const [], const [], const ColorScheme.light());

      final enumeratedCounts = provider.filteredDateEventCounts(null);
      expect(enumeratedCounts, {'2024-08-09': 1});
      for (final dateKey in enumeratedCounts.keys) {
        final dateParts = dateKey.split('-').map(int.parse).toList();
        final localQuery = DateTime(
          dateParts[0],
          dateParts[1],
          dateParts[2],
          21,
        );
        final utcQuery = DateTime.utc(
          dateParts[0],
          dateParts[1],
          dateParts[2],
          3,
        );
        _expectIdentityOrder(provider.getEventsForDate(localQuery), [
          mixedZoneFallback,
        ]);
        _expectIdentityOrder(provider.getEventsForDate(utcQuery), [
          mixedZoneFallback,
        ]);
        _expectIdentityOrder(_snapshot(provider, localQuery), [
          mixedZoneFallback,
        ]);
        _expectIdentityOrder(_snapshot(provider, utcQuery), [
          mixedZoneFallback,
        ]);
      }
      expect(provider.getEventsForDate(DateTime(2024, 8, 10)), isEmpty);
      expect(_snapshot(provider, DateTime.utc(2024, 8, 8)), isEmpty);
    },
  );

  test(
    'duplicates retain identity and queries do not mutate provider state',
    () {
      final provider = CalendarProvider();
      addTearDown(provider.dispose);
      final first = CalendarEvent(
        id: 'same-id',
        title: 'Duplicate occurrence',
        date: DateTime(2024, 9, 4, 9),
        type: CalendarEventType.event,
        color: Colors.green,
      );
      final secondWithSameId = CalendarEvent(
        id: 'same-id',
        title: 'Duplicate occurrence',
        date: DateTime(2024, 9, 4, 9),
        type: CalendarEventType.event,
        color: Colors.green,
      );
      provider.setExternalEvents([first, first, secondWithSameId]);
      provider.rebuild(const [], const [], const [], const ColorScheme.light());

      var notifications = 0;
      provider.addListener(() => notifications++);
      final originalEvents = provider.events;
      final originalRevision = provider.sourceRevision;
      final expected = [first, first, secondWithSameId];
      final localQuery = DateTime(2024, 9, 4, 23, 50);
      final utcQuery = DateTime.utc(2024, 9, 4, 4, 5);

      final getResult = provider.getEventsForDate(localQuery);
      _expectIdentityOrder(getResult, expected);
      _expectIdentityOrder(provider.getEventsForDate(utcQuery), expected);
      _expectIdentityOrder(_snapshot(provider, localQuery), expected);
      _expectIdentityOrder(_snapshot(provider, utcQuery), expected);
      getResult.add(secondWithSameId);
      expect(
        () => _snapshot(provider, localQuery).add(first),
        throwsA(isA<UnsupportedError>()),
      );

      final emptyGet = provider.getEventsForDate(DateTime(2024, 9, 5));
      expect(emptyGet, isEmpty);
      emptyGet.add(first);
      final emptySnapshot = _snapshot(provider, DateTime.utc(2024, 9, 5));
      expect(emptySnapshot, isEmpty);
      expect(() => emptySnapshot.add(first), throwsA(isA<UnsupportedError>()));

      expect(identical(provider.events, originalEvents), isTrue);
      _expectIdentityOrder(provider.events, expected);
      expect(provider.sourceRevision, originalRevision);
      expect(notifications, 0);
    },
  );

  test('date membership supports backend years without navigation bounds', () {
    final provider = CalendarProvider();
    addTearDown(provider.dispose);
    final events = [
      _singleDayEvent('year-minus-one', DateTime(-1, 1, 1)),
      _singleDayEvent('year-zero', DateTime(0, 1, 1)),
      _singleDayEvent('year-one', DateTime(1, 1, 1)),
      _singleDayEvent('year-9999', DateTime(9999, 12, 31)),
      _singleDayEvent('year-10000', DateTime(10000, 1, 1)),
    ];
    provider.setExternalEvents(events);
    provider.rebuild(const [], const [], const [], const ColorScheme.light());

    for (final event in events) {
      final localQuery = DateTime(
        event.date.year,
        event.date.month,
        event.date.day,
        22,
      );
      final utcQuery = DateTime.utc(
        event.date.year,
        event.date.month,
        event.date.day,
        3,
      );
      _expectIdentityOrder(provider.getEventsForDate(localQuery), [event]);
      _expectIdentityOrder(provider.getEventsForDate(utcQuery), [event]);
      _expectIdentityOrder(_snapshot(provider, localQuery), [event]);
      _expectIdentityOrder(_snapshot(provider, utcQuery), [event]);
    }
  });

  if (Platform.environment['DUOYI_REQUIRE_APIA'] == '1') {
    test('Apia UTC query for the skipped local civil date is empty', () {
      final localConstruction = DateTime(2011, 12, 30);
      expect(
        [
          localConstruction.year,
          localConstruction.month,
          localConstruction.day,
        ],
        [2011, 12, 31],
        reason: 'DUOYI_REQUIRE_APIA requires 2011-12-30 to be skipped locally',
      );

      final before = _singleDayEvent('apia-before', DateTime(2011, 12, 29));
      final after = _singleDayEvent('apia-after', DateTime(2011, 12, 31));
      final provider = CalendarProvider();
      addTearDown(provider.dispose);
      provider.setExternalEvents([before, after]);
      provider.rebuild(const [], const [], const [], const ColorScheme.light());

      final skippedUtcDay = DateTime.utc(2011, 12, 30);
      final skippedGet = provider.getEventsForDate(skippedUtcDay);
      expect(skippedGet, isEmpty);
      skippedGet.add(before);
      final skippedSnapshot = _snapshot(provider, skippedUtcDay);
      expect(skippedSnapshot, isEmpty);
      expect(
        () => skippedSnapshot.add(before),
        throwsA(isA<UnsupportedError>()),
      );
      _expectIdentityOrder(
        provider.getEventsForDate(DateTime.utc(2011, 12, 29)),
        [before],
      );
      _expectIdentityOrder(
        provider.getEventsForDate(DateTime.utc(2011, 12, 31)),
        [after],
      );
    });
  }

  if (Platform.environment['DUOYI_REQUIRE_DST'] == '1') {
    test('get and snapshot use civil fields across real DST start and end', () {
      final transitions = _localOffsetTransitions2026();
      final starts = transitions
          .where((transition) => transition.offsetChangeMinutes > 0)
          .toList();
      final ends = transitions
          .where((transition) => transition.offsetChangeMinutes < 0)
          .toList();
      expect(starts, isNotEmpty, reason: 'Expected a local DST start');
      expect(ends, isNotEmpty, reason: 'Expected a local DST end');

      final transitionsToCheck = [starts.first, ends.first];
      final events = [
        for (var index = 0; index < transitionsToCheck.length; index++)
          CalendarEvent(
            id: 'dst-span-$index',
            title: 'DST span $index',
            date: _localAtOffset(transitionsToCheck[index].day, -1, hour: 10),
            endDate: _localAtOffset(transitionsToCheck[index].day, 1, hour: 10),
            type: CalendarEventType.timeEntry,
            color: Colors.blue,
          ),
      ];
      final provider = CalendarProvider();
      addTearDown(provider.dispose);
      provider.setExternalEvents(events);
      provider.rebuild(const [], const [], const [], const ColorScheme.light());

      for (var index = 0; index < transitionsToCheck.length; index++) {
        final transition = transitionsToCheck[index].day;
        final previousNoon = DateTime(
          transition.year,
          transition.month,
          transition.day - 1,
          12,
        );
        expect(
          previousNoon.timeZoneOffset,
          isNot(transition.timeZoneOffset),
          reason: 'The DST fixture must cross an actual offset change',
        );
        for (final offset in [-1, 0, 1]) {
          final localQuery = _localAtOffset(transition, offset, hour: 23);
          final utcQuery = DateTime.utc(
            localQuery.year,
            localQuery.month,
            localQuery.day,
            2,
          );
          final expected = [events[index]];
          _expectIdentityOrder(provider.getEventsForDate(localQuery), expected);
          _expectIdentityOrder(provider.getEventsForDate(utcQuery), expected);
          _expectIdentityOrder(_snapshot(provider, localQuery), expected);
          _expectIdentityOrder(_snapshot(provider, utcQuery), expected);
        }
      }
    });
  }
}

List<CalendarEvent> _snapshot(
  CalendarProvider provider,
  DateTime date, {
  List<TodoItem> todos = const <TodoItem>[],
}) => provider.buildEventsForDateSnapshot(
  date,
  todos,
  const [],
  const [],
  const ColorScheme.light(),
);

CalendarEvent _singleDayEvent(String id, DateTime date) => CalendarEvent(
  id: id,
  title: id,
  date: date,
  type: CalendarEventType.event,
  color: Colors.blue,
);

List<String> _ids(List<CalendarEvent> events) =>
    events.map((event) => event.id).toList(growable: false);

void _expectIdentityOrder(
  List<CalendarEvent> actual,
  List<CalendarEvent> expected,
) {
  expect(_ids(actual), _ids(expected));
  expect(actual, hasLength(expected.length));
  for (var index = 0; index < expected.length; index++) {
    expect(actual[index], same(expected[index]));
  }
}

List<({DateTime day, int offsetChangeMinutes})> _localOffsetTransitions2026() {
  final transitions = <({DateTime day, int offsetChangeMinutes})>[];
  var prior = DateTime(2026, 1, 1, 12);
  for (var dayOfYear = 2; dayOfYear <= 365; dayOfYear++) {
    final current = DateTime(2026, 1, dayOfYear, 12);
    final change =
        current.timeZoneOffset.inMinutes - prior.timeZoneOffset.inMinutes;
    if (change != 0) {
      transitions.add((day: current, offsetChangeMinutes: change));
    }
    prior = current;
  }
  return transitions;
}

DateTime _localAtOffset(DateTime day, int offset, {required int hour}) {
  final target = DateTime.utc(
    day.year,
    day.month,
    day.day,
  ).add(Duration(days: offset));
  return DateTime(target.year, target.month, target.day, hour);
}
