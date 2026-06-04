import 'dart:math';

import 'package:test/test.dart';

import 'package:duoyi/models/goal.dart';
import 'package:duoyi/models/recurrence.dart';
import 'package:duoyi/services/holiday_calendar.dart';
import 'package:duoyi/services/recurrence_engine.dart';

/// RecurrenceEngine 属性测试（Task 22.3 / Properties P8 / P9 / P10 / P11）。
///
/// Feature: app-alignment-overhaul
/// Validates: Requirements 11.3 / 11.4 / 11.6 / 11.7
///
/// - P8: weekly 下 `1d ≤ next - anchor ≤ 7k d`
/// - P9: skipHolidays ⇒ `!HolidayCalendar.isHoliday(next)`（或窗口全节假日 → null）
/// - P10: 同 goalId 同 `yearWeek` 多次调用返回相同结果
/// - P11: `endDate ≠ null` ⇒ `next = null ∨ next ≤ endDate`
void main() {
  const int kSeed = 42;
  const int kIterations = 50;

  setUp(() {
    HolidayCalendar.resetOverrides();
  });

  DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  group('P8 - weekly frequency bound', () {
    test('1d ≤ next - anchor ≤ 7k d', () {
      final rng = Random(kSeed);
      for (int iter = 0; iter < kIterations; iter++) {
        final interval = 1 + rng.nextInt(4); // 1..4 周
        final rule = RecurrenceRule(
          frequency: RecurrenceFrequency.weekly,
          interval: interval,
        );
        final scheduling = const GoalScheduling.fixed();
        final anchor = DateTime(
          2025,
          1,
          1,
        ).add(Duration(days: rng.nextInt(300)));

        final nxt = RecurrenceEngine.nextOccurrence(
          rule: rule,
          scheduling: scheduling,
          skipHolidays: false,
          anchor: anchor,
        );

        expect(nxt, isNotNull, reason: 'iter=$iter weekly-fixed 应该永远有下一次');
        final delta = nxt!.difference(dateOnly(anchor)).inDays;
        expect(
          delta >= 1,
          isTrue,
          reason: 'iter=$iter anchor=$anchor next=$nxt delta=$delta',
        );
        expect(
          delta <= 7 * interval,
          isTrue,
          reason: 'iter=$iter anchor=$anchor next=$nxt delta=$delta',
        );
      }
    });
  });

  group('P11 - endDate upper bound', () {
    test('next = null ∨ next ≤ endDate', () {
      final rng = Random(kSeed);
      for (int iter = 0; iter < kIterations; iter++) {
        final daysAhead = 1 + rng.nextInt(60);
        final anchor = DateTime(2025, 3, 15);
        final endDate = anchor.add(Duration(days: daysAhead));
        final rule = RecurrenceRule(
          frequency: RecurrenceFrequency.daily,
          interval: 1 + rng.nextInt(3),
          endDate: endDate,
        );
        final nxt = RecurrenceEngine.nextOccurrence(
          rule: rule,
          scheduling: const GoalScheduling.fixed(),
          skipHolidays: false,
          anchor: anchor,
        );
        if (nxt != null) {
          expect(
            nxt.isAfter(dateOnly(endDate)),
            isFalse,
            reason: 'iter=$iter next=$nxt > endDate=$endDate',
          );
        }
      }
    });
  });

  group('P10 - random stable within yearWeek', () {
    test('同 goalId 同 yearWeek 两次调用返回相同日期', () {
      final rng = Random(kSeed);
      for (int iter = 0; iter < kIterations; iter++) {
        final anchor = DateTime(
          2025,
          3,
          3,
        ).add(Duration(days: rng.nextInt(180)));
        final rule = const RecurrenceRule(
          frequency: RecurrenceFrequency.weekly,
          interval: 1,
        );
        final scheduling = const GoalScheduling.random(minGapDays: 1);
        final goalId = 'goal-$iter';

        final first = RecurrenceEngine.nextOccurrence(
          rule: rule,
          scheduling: scheduling,
          skipHolidays: false,
          anchor: anchor,
          goalId: goalId,
        );
        final second = RecurrenceEngine.nextOccurrence(
          rule: rule,
          scheduling: scheduling,
          skipHolidays: false,
          anchor: anchor,
          goalId: goalId,
        );
        expect(
          first,
          second,
          reason: 'iter=$iter goalId=$goalId first=$first second=$second',
        );
      }
    });
  });

  group('P9 - skipHolidays', () {
    test('返回的 next 不在节假日上（除非整窗口节假日，则 null）', () {
      // 人工注入一段连续节假日窗口做测试：3-05 ~ 3-09。
      HolidayCalendar.updateFrom(
        2025,
        const HolidayYear(
          holidays: <String>{
            '03-05',
            '03-06',
            '03-07',
            '03-08',
            '03-09',
            '03-10',
          },
          workMakeupDays: <String>{},
        ),
      );
      final rule = const RecurrenceRule(
        frequency: RecurrenceFrequency.daily,
        interval: 1,
      );
      // anchor 3-04 → next 若不跳节假日应是 3-05；开启跳节假日后应前推到 3-11。
      final withoutSkip = RecurrenceEngine.nextOccurrence(
        rule: rule,
        scheduling: const GoalScheduling.fixed(),
        skipHolidays: false,
        anchor: DateTime(2025, 3, 4),
      );
      expect(withoutSkip, DateTime(2025, 3, 5));

      final withSkip = RecurrenceEngine.nextOccurrence(
        rule: rule,
        scheduling: const GoalScheduling.fixed(),
        skipHolidays: true,
        anchor: DateTime(2025, 3, 4),
      );
      expect(withSkip, isNotNull);
      expect(HolidayCalendar.isHoliday(withSkip!), isFalse);
      expect(withSkip.isBefore(DateTime(2025, 3, 11)), isFalse);
    });
  });

  group('frequency = none 返回 null', () {
    test('none 无论 anchor 都返回 null', () {
      final nxt = RecurrenceEngine.nextOccurrence(
        rule: const RecurrenceRule(),
        scheduling: const GoalScheduling.fixed(),
        skipHolidays: false,
        anchor: DateTime(2025, 5, 1),
      );
      expect(nxt, isNull);
    });
  });
}
