import 'package:duoyi/core/calendar_aggregator.dart';
import 'package:duoyi/models/calendar_event.dart';
import 'package:duoyi/models/pomodoro.dart';
import 'package:duoyi/providers/calendar_provider.dart';
import 'package:duoyi/services/widget_schedule_detail.dart';
import 'package:duoyi/services/widget_schedule_projection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const id = '  object /?#&=% 测试🌙  ';
  final day = DateTime(2026, 10, 20, 9);
  CalendarEvent event(CalendarEventType type, {String? sourceId = id}) =>
      CalendarEvent(
        id: id,
        title: 'Literal title',
        date: day,
        type: type,
        color: Colors.blue,
        sourceId: sourceId,
      );

  const hosts = {
    CalendarEventType.todo: 'todo',
    CalendarEventType.habit: 'habit',
    CalendarEventType.course: 'course',
    CalendarEventType.anniversary: 'anniversary',
    CalendarEventType.diary: 'diary',
    CalendarEventType.goal: 'goal',
    CalendarEventType.countdown: 'countdown',
    CalendarEventType.timeEntry: 'time-entry',
    CalendarEventType.event: 'event',
    CalendarEventType.pomodoro: 'pomodoro',
  };
  for (final type in CalendarEventType.values) {
    test('publisher retains opaque ${type.name} identity', () {
      final uri = Uri.parse(homeWidgetScheduleEventDeepLink(event(type)));
      expect(uri.host, hosts[type], reason: type.name);
      expect(uri.pathSegments, [id], reason: type.name);
      expect(uri.hasQuery, isFalse);
    });
  }

  test('legacy local event remains projected by its own stored ID', () {
    final stored = event(CalendarEventType.event, sourceId: null);
    final projected = homeWidgetScheduleEvents([stored]);
    expect(projected, [stored]);
    final target = Uri.parse(homeWidgetScheduleEventDeepLink(projected.single));
    expect(target.host, 'event');
    expect(target.pathSegments, [stored.id]);
    expect(
      widgetScheduleDetailEvent(
        target,
        localEvents: [stored],
        sessions: const [],
        colorScheme: const ColorScheme.light(),
      ),
      same(stored),
    );
  });

  test(
    'published local ID resolves stored object even with other sourceId',
    () async {
      SharedPreferences.setMockInitialValues({});
      final calendar = CalendarProvider();
      try {
        await calendar.loadFromStorage();
        await calendar.addLocalEvent(
          event(CalendarEventType.event, sourceId: 'source-alias'),
        );
        final stored = calendar.localEvents.single;
        final target = Uri.parse(homeWidgetScheduleEventDeepLink(stored));
        expect(target.host, 'event');
        expect(target.pathSegments, [stored.id]);
        final resolved = widgetScheduleDetailEvent(
          target,
          localEvents: calendar.localEvents,
          sessions: const [],
          colorScheme: const ColorScheme.light(),
        );
        expect(identical(resolved, stored), isTrue);
        expect(resolved!.sourceId, 'source-alias');
      } finally {
        calendar.dispose();
      }
    },
  );

  test(
    'real focus aggregation publishes and resolves the exact historical session',
    () {
      final session = PomodoroSession(
        id: id,
        startTime: day,
        endTime: day.add(const Duration(minutes: 25)),
        durationSeconds: 1500,
        type: PomodoroType.focus,
        taskName: 'Literal focus',
      );
      final projected = homeWidgetScheduleEvents(
        CalendarAggregator.buildEvents(
          todos: const [],
          habits: const [],
          pomodoroSessions: [session],
          colorScheme: const ColorScheme.light(),
        ),
      );
      final target = Uri.parse(
        homeWidgetScheduleEventDeepLink(projected.single),
      );
      expect(target.host, 'pomodoro');
      expect(target.pathSegments, [id]);
      final resolved = widgetScheduleDetailEvent(
        target,
        localEvents: const [],
        sessions: [session],
        colorScheme: const ColorScheme.light(),
      );
      expect(resolved!.sourceId, session.id);
      expect(resolved.date, session.startTime);
      expect(resolved.endDate, session.endTime);
      expect(resolved.title, 'Literal focus');
    },
  );

  test('receiver splits once and does not trim a valid object identity', () {
    for (final host in ['event', 'pomodoro']) {
      final uri = Uri.parse(
        'duoyi://$host/${Uri.encodeComponent(id)}'
        '?source=widget&widget_day=2026-10-20&widget_offset=0&widget_account=owner&widget_delivery=tap',
      );
      expect(widgetScheduleDetailId(uri), id);
      expect(
        widgetScheduleDetailId(Uri.parse('duoyi://$host/first%2Fsecond')),
        'first/second',
      );
    }
  });

  test('receiver rejects ambiguous malformed or unrelated object links', () {
    for (final raw in [
      '',
      'https://event/id',
      'duoyi://event',
      'duoyi://event/',
      'duoyi://event/%20%0A',
      'duoyi://event/a/b',
      'duoyi://event//a',
      'duoyi://event/a/',
      'duoyi://event/%FF',
      'duoyi://pomodoro/a?widget_account=A&widget_account=B',
      'duoyi://event/a?extra=1',
      'duoyi://user@event/a',
      'duoyi://event:90/a',
      'duoyi://pomodoro/a#fragment',
      'duoyi://focus/a',
      'duoyi://calendar/a',
    ]) {
      expect(widgetScheduleDetailId(Uri.parse(raw)), isNull, reason: raw);
    }
  });

  test(
    'missing objects and break sessions never select a different record',
    () {
      final session = PomodoroSession(
        id: id,
        startTime: day,
        endTime: day.add(const Duration(minutes: 5)),
        durationSeconds: 300,
        type: PomodoroType.shortBreak,
      );
      for (final uri in [
        'duoyi://event/missing',
        'duoyi://pomodoro/missing',
        'duoyi://pomodoro/${Uri.encodeComponent(id)}',
      ]) {
        expect(
          widgetScheduleDetailEvent(
            Uri.parse(uri),
            localEvents: [event(CalendarEventType.event)],
            sessions: [session],
            colorScheme: const ColorScheme.light(),
          ),
          isNull,
        );
      }
    },
  );
}
