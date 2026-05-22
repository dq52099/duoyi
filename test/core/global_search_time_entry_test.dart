import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'package:duoyi/core/global_search.dart';
import 'package:duoyi/models/calendar_event.dart';
import 'package:duoyi/models/time_entry.dart';

void main() {
  group('GlobalSearch TimeEntry 覆盖', () {
    test('TimeEntry 标题命中', () {
      final entries = <TimeEntry>[
        TimeEntry(
          id: 'e1',
          title: '阅读《时间足迹》',
          startAt: DateTime(2026, 5, 1, 9),
          endAt: DateTime(2026, 5, 1, 10),
          category: TimeEntryCategory.focus,
          source: TimeEntrySource.manual,
        ),
        TimeEntry(
          id: 'e2',
          title: '另一项',
          startAt: DateTime(2026, 5, 1, 11),
          endAt: DateTime(2026, 5, 1, 12),
          category: TimeEntryCategory.focus,
          source: TimeEntrySource.manual,
        ),
      ];

      final hits = GlobalSearch.run(
        query: '时间足迹',
        todos: const [],
        habits: const [],
        notes: const [],
        diaries: const [],
        anniversaries: const [],
        countdowns: const [],
        goals: const [],
        courses: const [],
        timeEntries: entries,
      );

      expect(hits, hasLength(1));
      expect(hits.first.kind, SearchKind.timeEntry);
      expect(hits.first.title, '阅读《时间足迹》');
    });

    test('空查询返回空结果', () {
      final hits = GlobalSearch.run(
        query: '',
        todos: const [],
        habits: const [],
        notes: const [],
        diaries: const [],
        anniversaries: const [],
        countdowns: const [],
        goals: const [],
        courses: const [],
        timeEntries: const [],
      );
      expect(hits, isEmpty);
    });

    test('TimeEntry 备注命中', () {
      final entries = <TimeEntry>[
        TimeEntry(
          id: 'e1',
          title: '专注',
          note: '攻克难点',
          startAt: DateTime(2026, 5, 1, 9),
          endAt: DateTime(2026, 5, 1, 10),
          category: TimeEntryCategory.focus,
          source: TimeEntrySource.manual,
        ),
      ];

      final hits = GlobalSearch.run(
        query: '难点',
        todos: const [],
        habits: const [],
        notes: const [],
        diaries: const [],
        anniversaries: const [],
        countdowns: const [],
        goals: const [],
        courses: const [],
        timeEntries: entries,
      );

      expect(hits, hasLength(1));
      expect(hits.first.kind, SearchKind.timeEntry);
      expect(hits.first.subtitle, '攻克难点');
    });

    test('CalendarEvent 本地/订阅日程命中但不重复聚合待办', () {
      final events = <CalendarEvent>[
        CalendarEvent(
          id: 'local-event-1',
          title: '客户复盘会议',
          date: DateTime(2026, 5, 2, 14),
          type: CalendarEventType.event,
          sourceId: 'local-event-1',
          subtitle: '会议室 A',
          note: '准备复盘材料',
          projectName: '客户项目',
          color: const Color(0xFF5B6EE1),
        ),
        CalendarEvent(
          id: 'todo-calendar-1',
          title: '客户复盘待办',
          date: DateTime(2026, 5, 2),
          type: CalendarEventType.todo,
          sourceId: 'todo-1',
          color: const Color(0xFF5B6EE1),
        ),
      ];

      final hits = GlobalSearch.run(
        query: '复盘',
        todos: const [],
        habits: const [],
        notes: const [],
        diaries: const [],
        anniversaries: const [],
        countdowns: const [],
        goals: const [],
        courses: const [],
        calendarEvents: events,
        timeEntries: const [],
      );

      expect(hits, hasLength(1));
      expect(hits.first.kind, SearchKind.calendarEvent);
      expect(hits.first.title, '客户复盘会议');
      expect(hits.first.subtitle, '会议室 A');
      expect(hits.first.sourceId, 'local-event-1');
      expect(hits.first.when, DateTime(2026, 5, 2, 14));
    });
  });
}
