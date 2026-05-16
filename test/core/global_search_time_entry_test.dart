import 'package:flutter_test/flutter_test.dart';

import 'package:duoyi/core/global_search.dart';
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
  });
}
