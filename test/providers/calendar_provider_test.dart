import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:duoyi/models/calendar_event.dart';
import 'package:duoyi/models/habit.dart';
import 'package:duoyi/providers/calendar_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('CalendarProvider rebuilds habit events when only unit changes', () {
    final provider = CalendarProvider();
    final colorScheme = const ColorScheme.light();
    final habit = Habit(
      id: 'drink-water',
      name: '喝水',
      targetCount: 2,
      unit: '次',
      completions: const {'2026-05-12': 1},
    );

    provider.rebuild(const [], [habit], const [], colorScheme);
    expect(
      provider.events
          .singleWhere((e) => e.type == CalendarEventType.habit)
          .subtitle,
      '1 次 / 2 次',
    );

    provider.rebuild(
      const [],
      [habit.copyWith(unit: '杯')],
      const [],
      colorScheme,
    );

    expect(
      provider.events
          .singleWhere((e) => e.type == CalendarEventType.habit)
          .subtitle,
      '1 杯 / 2 杯',
    );
  });

  test(
    'CalendarProvider indexes timed multi-day events on each covered date',
    () {
      final provider = CalendarProvider();
      final colorScheme = const ColorScheme.light();
      final event = CalendarEvent(
        id: 'external-trip',
        title: '出差',
        date: DateTime(2026, 5, 20, 10),
        endDate: DateTime(2026, 5, 22, 9),
        type: CalendarEventType.timeEntry,
        color: Colors.blue,
        time: const TimeOfDay(hour: 10, minute: 0),
      );

      provider.setExternalEvents([event]);
      provider.rebuild(const [], const [], const [], colorScheme);

      expect(provider.getEventsForDate(DateTime(2026, 5, 20)), [event]);
      expect(provider.getEventsForDate(DateTime(2026, 5, 21)), [event]);
      expect(provider.getEventsForDate(DateTime(2026, 5, 22)), [event]);
      expect(provider.getEventsForDate(DateTime(2026, 5, 23)), isEmpty);
      expect(
        provider.dateEventTypes['2026-05-21'],
        contains(CalendarEventType.timeEntry),
      );
      expect(provider.datesWithEvents, contains(DateTime(2026, 5, 21)));
    },
  );

  test('CalendarProvider treats all-day midnight DTEND as exclusive', () {
    final provider = CalendarProvider();
    final colorScheme = const ColorScheme.light();
    final event = CalendarEvent(
      id: 'external-all-day',
      title: '全天活动',
      date: DateTime(2026, 5, 20),
      endDate: DateTime(2026, 5, 21),
      type: CalendarEventType.timeEntry,
      color: Colors.green,
    );

    provider.setExternalEvents([event]);
    provider.rebuild(const [], const [], const [], colorScheme);

    expect(provider.getEventsForDate(DateTime(2026, 5, 20)), [event]);
    expect(provider.getEventsForDate(DateTime(2026, 5, 21)), isEmpty);
    expect(
      provider.dateEventTypes['2026-05-20'],
      contains(CalendarEventType.timeEntry),
    );
    expect(provider.dateEventTypes['2026-05-21'], isNull);
  });

  test(
    'CalendarProvider applies span indexes after type and project filters',
    () {
      final provider = CalendarProvider();
      final colorScheme = const ColorScheme.light();
      final todo = CalendarEvent(
        id: 'todo-long',
        title: '长任务',
        date: DateTime(2026, 5, 20, 9),
        endDate: DateTime(2026, 5, 22, 18),
        type: CalendarEventType.todo,
        color: Colors.orange,
        projectId: 'work',
        time: const TimeOfDay(hour: 9, minute: 0),
      );
      final other = CalendarEvent(
        id: 'time-long',
        title: '长时间记录',
        date: DateTime(2026, 5, 20, 10),
        endDate: DateTime(2026, 5, 22, 12),
        type: CalendarEventType.timeEntry,
        color: Colors.blue,
        time: const TimeOfDay(hour: 10, minute: 0),
      );

      provider.setExternalEvents([todo, other]);
      provider.rebuild(const [], const [], const [], colorScheme);

      expect(
        provider.getEventsForDate(
          DateTime(2026, 5, 21),
          activeTypes: {CalendarEventType.todo},
          projectKey: 'work',
        ),
        [todo],
      );
      expect(
        provider.filteredDateEventTypes({
          CalendarEventType.todo,
        }, projectKey: 'work')['2026-05-21'],
        [CalendarEventType.todo],
      );
    },
  );

  test('CalendarProvider filters shared events by workspace', () {
    final provider = CalendarProvider();
    final colorScheme = const ColorScheme.light();
    final privateTime = CalendarEvent(
      id: 'time-private',
      title: '个人记录',
      date: DateTime(2026, 5, 20),
      type: CalendarEventType.timeEntry,
      color: Colors.green,
    );
    final sharedGoal = CalendarEvent(
      id: 'goal-shared',
      title: '共享目标',
      date: DateTime(2026, 5, 20),
      type: CalendarEventType.goal,
      color: Colors.blue,
      workspaceId: 'workspace-1',
    );
    final sharedEvent = CalendarEvent(
      id: 'event-shared',
      title: '共享日程',
      date: DateTime(2026, 5, 20),
      type: CalendarEventType.event,
      color: Colors.orange,
      workspaceId: 'workspace-1',
    );

    provider.setExternalEvents([privateTime, sharedGoal, sharedEvent]);
    provider.rebuild(const [], const [], const [], colorScheme);

    expect(
      provider.getEventsForDate(
        DateTime(2026, 5, 20),
        workspaceId: 'workspace-1',
      ),
      [sharedGoal, sharedEvent],
    );
    expect(
      provider.filteredDateEventTypes(
        null,
        workspaceId: 'workspace-1',
      )['2026-05-20'],
      [CalendarEventType.goal, CalendarEventType.event],
    );
  });

  test(
    'CalendarProvider bumps sourceRevision only for changed external events',
    () {
      final provider = CalendarProvider();
      final event = CalendarEvent(
        id: 'external-stable',
        title: '订阅日程',
        date: DateTime(2026, 5, 20),
        type: CalendarEventType.event,
        color: Colors.orange,
      );

      expect(provider.sourceRevision, 0);

      provider.setExternalEvents([event]);
      expect(provider.sourceRevision, 1);

      provider.setExternalEvents([event]);
      expect(provider.sourceRevision, 1);

      provider.setExternalEvents([event.copyWith(title: '订阅日程更新')]);
      expect(provider.sourceRevision, 2);
    },
  );
}
