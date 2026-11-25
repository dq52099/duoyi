import 'dart:io';

import 'package:duoyi/core/calendar_aggregator.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/calendar_event.dart';
import 'package:duoyi/models/habit.dart';
import 'package:duoyi/models/pomodoro.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/services/widget_schedule_projection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => I18n.setLocale(AppLocale.zh));
  tearDown(() => I18n.setLocale(AppLocale.zh));

  group('homeWidgetScheduleEvents', () {
    test('uses actual timed todo starts for the widget top three', () {
      final day = DateTime(2026, 10, 11);
      final events = CalendarAggregator.buildEvents(
        todos: [
          _timedTodo(id: 'a', title: 'A afternoon', day: day, hour: 15),
          _timedTodo(id: 'b', title: 'B afternoon', day: day, hour: 16),
          _timedTodo(id: 'c', title: 'C afternoon', day: day, hour: 17),
          _timedTodo(id: 'z', title: 'Z morning', day: day, hour: 9),
        ],
        habits: const <Habit>[],
        pomodoroSessions: const <PomodoroSession>[],
        colorScheme: const ColorScheme.light(),
        now: DateTime(2026, 10, 11, 8),
      );

      final projected = homeWidgetScheduleEvents(events);

      expect(projected.take(3).map((event) => event.title).toList(), [
        'Z morning',
        'A afternoon',
        'B afternoon',
      ]);
      expect(projected.take(3).map(homeWidgetScheduleEventLabel).toList(), [
        '09:00 待办 · Z morning',
        '15:00 待办 · A afternoon',
        '16:00 待办 · B afternoon',
      ]);
    });

    test(
      'combines date clocks, explicit time overrides, and all-day dates',
      () {
        final day = DateTime(2026, 10, 11);
        final events = [
          _event(
            id: 'date-clock',
            title: 'Date clock',
            sourceId: 'date-clock',
            date: DateTime(2026, 10, 11, 18, 30),
          ),
          _event(
            id: 'time-override',
            title: 'Time override',
            sourceId: 'time-override',
            date: DateTime(2026, 10, 11, 18, 30),
            time: const TimeOfDay(hour: 9, minute: 15),
          ),
          _event(
            id: 'all-day',
            title: 'All day',
            sourceId: 'all-day',
            date: day,
          ),
          _event(
            id: 'late-override',
            title: 'Late override',
            sourceId: 'late-override',
            date: DateTime(2026, 10, 11, 7),
            time: const TimeOfDay(hour: 21, minute: 5),
          ),
        ];
        final originalOrder = List<CalendarEvent>.of(events);
        final originalValues = events.map((event) => event.toJson()).toList();

        final projected = homeWidgetScheduleEvents(events);

        expect(projected.map((event) => event.id).toList(), [
          'all-day',
          'time-override',
          'date-clock',
          'late-override',
        ]);
        expect(events.map((event) => event.id).toList(), [
          'date-clock',
          'time-override',
          'all-day',
          'late-override',
        ]);
        expect(events.map((event) => event.toJson()).toList(), originalValues);
        for (var i = 0; i < events.length; i++) {
          expect(identical(events[i], originalOrder[i]), isTrue);
        }
      },
    );

    test('filters invalid source IDs and only completed todos', () {
      final day = DateTime(2026, 10, 11);
      final events = [
        _event(
          id: 'completed-todo',
          title: 'Completed todo',
          sourceId: 'completed-todo',
          date: day,
          type: CalendarEventType.todo,
          isCompleted: true,
        ),
        _event(
          id: 'missing-id',
          title: 'Missing source ID',
          sourceId: null,
          date: day.add(const Duration(hours: 1)),
          type: CalendarEventType.todo,
        ),
        _event(
          id: 'blank-id',
          title: 'Blank source ID',
          sourceId: ' \n\t ',
          date: day.add(const Duration(hours: 2)),
          type: CalendarEventType.todo,
        ),
        _event(
          id: 'completed-habit',
          title: 'Completed habit',
          sourceId: 'habit-1',
          date: day.add(const Duration(hours: 3)),
          type: CalendarEventType.habit,
          isCompleted: true,
        ),
        _event(
          id: 'valid-todo',
          title: 'Valid todo',
          sourceId: '  todo-1  ',
          date: day.add(const Duration(hours: 4)),
          type: CalendarEventType.todo,
        ),
        _event(
          id: 'completed-pomodoro',
          title: 'Completed focus',
          sourceId: 'focus-1',
          date: day.add(const Duration(hours: 5)),
          type: CalendarEventType.pomodoro,
          isCompleted: true,
        ),
      ];

      final projected = homeWidgetScheduleEvents(events);

      expect(projected.map((event) => event.id).toList(), [
        'completed-habit',
        'valid-todo',
        'completed-pomodoro',
      ]);
      expect(
        projected
            .firstWhere((event) => event.id == 'completed-habit')
            .isCompleted,
        isTrue,
      );
      expect(
        projected.firstWhere((event) => event.id == 'valid-todo').sourceId,
        '  todo-1  ',
      );
      expect(projected.last.isCompleted, isTrue);
    });

    test('breaks equal starts by raw title and then event ID', () {
      final start = DateTime(2026, 10, 11, 9);
      final events = [
        _event(id: 'z-id', title: 'Same title', sourceId: 'z', date: start),
        _event(id: 'title-z', title: 'Z title', sourceId: 'z2', date: start),
        _event(id: 'a-id', title: 'Same title', sourceId: 'a', date: start),
        _event(id: 'title-a', title: 'A title', sourceId: 'a2', date: start),
      ];

      final projected = homeWidgetScheduleEvents(events);

      expect(projected.map((event) => event.id).toList(), [
        'title-a',
        'a-id',
        'z-id',
        'title-z',
      ]);
    });
  });

  test(
    'event labels localize metadata fallbacks and preserve literal titles',
    () {
      final focusFallback = _event(
        id: 'focus-fallback',
        title: '专注 25 分钟',
        sourceId: 'focus-fallback',
        date: DateTime(2026, 10, 11, 9),
        type: CalendarEventType.pomodoro,
        time: const TimeOfDay(hour: 9, minute: 0),
        displayMetadata: const PomodoroDisplayMetadata(
          fallbackMinutes: 25,
          durationSeconds: 1500,
        ),
      );
      final diaryFallback = _event(
        id: 'diary-fallback',
        title: '10月11日的日记',
        sourceId: 'diary-fallback',
        date: DateTime(2026, 10, 11, 10),
        type: CalendarEventType.diary,
        time: const TimeOfDay(hour: 10, minute: 0),
        displayMetadata: DiaryDisplayMetadata(
          fallbackTitleDate: DateTime(2026, 10, 11),
        ),
      );
      final authoredFocus = _event(
        id: 'authored-focus',
        title: '专注 25 分钟',
        sourceId: 'authored-focus',
        date: DateTime(2026, 10, 11, 11),
        type: CalendarEventType.pomodoro,
        time: const TimeOfDay(hour: 11, minute: 0),
      );
      final legacyDiary = _event(
        id: 'legacy-diary',
        title: '10月11日的日记',
        sourceId: 'legacy-diary',
        date: DateTime(2026, 10, 11, 12),
        type: CalendarEventType.diary,
        time: const TimeOfDay(hour: 12, minute: 0),
      );

      expect(
        homeWidgetScheduleEventLabel(focusFallback),
        '09:00 番茄钟 · 专注 25 分钟',
      );
      expect(
        homeWidgetScheduleEventLabel(diaryFallback),
        '10:00 日记 · 10月11日的日记',
      );

      I18n.setLocale(AppLocale.en);
      expect(
        homeWidgetScheduleEventLabel(focusFallback),
        '09:00 Pomodoro · Focus 25 min',
      );
      expect(
        homeWidgetScheduleEventLabel(diaryFallback),
        '10:00 Diary · Diary for 10/11',
      );
      expect(
        homeWidgetScheduleEventLabel(authoredFocus),
        '11:00 Pomodoro · 专注 25 分钟',
      );
      expect(
        homeWidgetScheduleEventLabel(legacyDiary),
        '12:00 Diary · 10月11日的日记',
      );

      I18n.setLocale(AppLocale.zh);
      expect(
        homeWidgetScheduleEventLabel(focusFallback),
        '09:00 番茄钟 · 专注 25 分钟',
      );
      expect(
        homeWidgetScheduleEventLabel(diaryFallback),
        '10:00 日记 · 10月11日的日记',
      );
      expect(
        homeWidgetScheduleEventLabel(authoredFocus),
        '11:00 番茄钟 · 专注 25 分钟',
      );
      expect(homeWidgetScheduleEventLabel(legacyDiary), '12:00 日记 · 10月11日的日记');
    },
  );

  test('main schedule and label wrappers delegate to the helpers', () {
    final main = File('lib/main.dart').readAsStringSync();
    final pushStart = main.indexOf('Future<bool> _pushHomeWidget(');
    final scheduleStart = main.indexOf(
      'List<CalendarEvent> _homeWidgetEventsForToday(',
    );
    final labelStart = main.indexOf('String _homeWidgetEventLabel(');
    final deepLinkStart = main.indexOf('String _homeWidgetEventDeepLink(');
    expect(pushStart, isNonNegative);
    expect(scheduleStart, greaterThan(pushStart));
    expect(labelStart, greaterThan(scheduleStart));
    expect(deepLinkStart, greaterThan(labelStart));
    final pushBody = main.substring(pushStart, scheduleStart);
    final scheduleBody = main.substring(scheduleStart, labelStart);
    final labelBody = main.substring(labelStart, deepLinkStart);

    expect(
      pushBody,
      matches(RegExp(r'\.map\s*\(\s*_homeWidgetEventLabel\s*\)')),
    );
    expect(
      scheduleBody,
      matches(
        RegExp(
          r'return\s+homeWidgetScheduleEvents\s*\(\s*calendar\.buildEventsForDateSnapshot\s*\(',
        ),
      ),
    );
    expect(labelBody, contains('homeWidgetScheduleEventLabel(event)'));
  });
}

TodoItem _timedTodo({
  required String id,
  required String title,
  required DateTime day,
  required int hour,
}) => TodoItem(
  id: id,
  title: title,
  date: day,
  dueDate: DateTime(day.year, day.month, day.day, hour),
);

CalendarEvent _event({
  required String id,
  required String title,
  required String? sourceId,
  required DateTime date,
  CalendarEventType type = CalendarEventType.event,
  TimeOfDay? time,
  bool isCompleted = false,
  CalendarEventDisplayMetadata? displayMetadata,
}) => CalendarEvent(
  id: id,
  title: title,
  date: date,
  type: type,
  color: Colors.blue,
  sourceId: sourceId,
  time: time,
  isCompleted: isCompleted,
  displayMetadata: displayMetadata,
);
