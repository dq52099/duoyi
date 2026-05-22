import 'package:test/test.dart';

import 'package:duoyi/models/recurrence.dart';

void main() {
  group('RecurrenceRule interval semantics', () {
    test('weekly single weekday respects interval', () {
      const rule = RecurrenceRule(
        frequency: RecurrenceFrequency.weekly,
        interval: 2,
        byWeekdays: [0],
      );

      expect(rule.nextAfter(DateTime(2026, 5, 18, 9)), DateTime(2026, 6, 1, 9));
    });

    test('weekly multiple weekdays keeps later day in current active week', () {
      const rule = RecurrenceRule(
        frequency: RecurrenceFrequency.weekly,
        interval: 2,
        byWeekdays: [0, 2],
      );

      expect(
        rule.nextAfter(DateTime(2026, 5, 18, 9)),
        DateTime(2026, 5, 20, 9),
      );
      expect(rule.nextAfter(DateTime(2026, 5, 20, 9)), DateTime(2026, 6, 1, 9));
    });

    test('date-only endDate includes occurrences on that whole day', () {
      const rule = RecurrenceRule(frequency: RecurrenceFrequency.daily);
      final bounded = rule.copyWith(endDate: DateTime(2026, 5, 11));

      expect(
        bounded.nextAfter(DateTime(2026, 5, 10, 9)),
        DateTime(2026, 5, 11, 9),
      );
      expect(bounded.nextAfter(DateTime(2026, 5, 11, 9)), isNull);
    });

    test('weekly recurrence checks endDate before returning next weekday', () {
      const rule = RecurrenceRule(
        frequency: RecurrenceFrequency.weekly,
        byWeekdays: [0, 2],
      );
      final bounded = rule.copyWith(endDate: DateTime(2026, 5, 19));

      expect(bounded.nextAfter(DateTime(2026, 5, 18, 9)), isNull);
    });

    test('label includes weekdays, end date and max occurrences', () {
      final rule = RecurrenceRule(
        frequency: RecurrenceFrequency.weekly,
        interval: 2,
        byWeekdays: [0, 2],
        endDate: DateTime(2026, 5, 20),
        maxOccurrences: 10,
      );

      expect(rule.label, '每 2 周 · 一/三 · 至 2026-05-20 · 共 10 次');
    });

    test('none label stays compact', () {
      final rule = RecurrenceRule(
        endDate: DateTime(2026, 5, 20),
        maxOccurrences: 10,
      );

      expect(rule.label, '不重复');
    });
  });
}
