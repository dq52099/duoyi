import 'package:flutter_test/flutter_test.dart';

import 'package:duoyi/models/time_entry.dart';

void main() {
  test('TimeEntry JSON roundtrip preserves core fields', () {
    final original = TimeEntry(
      id: 'entry-1',
      title: '阅读',
      startAt: DateTime(2026, 5, 11, 8, 0),
      endAt: DateTime(2026, 5, 11, 8, 30),
      category: TimeEntryCategory.study,
      source: TimeEntrySource.manual,
      sourceId: 'book-1',
      dedupeKey: 'manual:1',
      note: '晨读',
      createdAt: DateTime(2026, 5, 11, 8, 0),
      updatedAt: DateTime(2026, 5, 11, 8, 30),
    );

    final decoded = TimeEntry.fromJson(original.toJson());
    expect(decoded.toJson(), equals(original.toJson()));
  });

  test('TimeEntry.fromJson accepts enum names for compatibility', () {
    final entry = TimeEntry.fromJson({
      'id': 'entry-2',
      'title': '跑步',
      'startAt': '2026-05-11T07:00:00.000',
      'endAt': '2026-05-11T07:45:00.000',
      'category': 'work',
      'source': 'habit',
      'sourceId': 'habit-1',
      'dedupeKey': 'habit:1',
      'note': '户外',
      'createdAt': '2026-05-11T07:00:00.000',
      'updatedAt': '2026-05-11T07:45:00.000',
    });

    expect(entry.category, TimeEntryCategory.work);
    expect(entry.source, TimeEntrySource.habit);
    expect(entry.note, '户外');
  });
}
