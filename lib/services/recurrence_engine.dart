/// RecurrenceEngine（Task 22.1 / Requirements 11）。
///
/// 统一处理"下一次派发日"的计算：
/// - `scheduling.mode == fixed` 走 [RecurrenceRule.nextAfter] 的基础路径；
/// - `scheduling.mode == random` 在 `[anchor + minGap, upperBound]` 范围内
///   用 `stableSeed(goalId, yearWeek)` 采样（同一周内结果稳定，P10）；
/// - `skipHolidays` 通过 [HolidayCalendar.isHoliday] 跳过，若整个窗口都是
///   节假日，回落到窗口内最后一个非节假日；仍无则返回 null（P9）；
/// - 所有返回值都是**本地日**（`DateTime(y, m, d)`，hour/minute/second=0）。
///
/// 不引入 `package:flutter/*` —— 纯 Dart，便于 PBT 单测。
library;

import '../models/goal.dart';
import '../models/recurrence.dart';
import 'holiday_calendar.dart';

/// `materializeTodayFromRecurring` 的返回值：匹配的 GoalItem 列表。
typedef GoalOccurrenceCallback = void Function(GoalItem goal, DateTime when);

class RecurrenceEngine {
  RecurrenceEngine._();

  static final RecurrenceEngine instance = RecurrenceEngine._();

  /// 给定 rule + scheduling + skipHolidays + anchor，返回下一个触发日。
  ///
  /// 返回值在本地时区下是"日"对齐（`DateTime(y, m, d)`）；无法计算时返回 null
  /// （例如 rule.frequency=none，或窗口全被节假日占用，或越过 endDate）。
  ///
  /// [goalId] 仅在 `scheduling.mode == random` 时用于稳定种子；fixed 模式忽略。
  static DateTime? nextOccurrence({
    required RecurrenceRule rule,
    required GoalScheduling scheduling,
    required bool skipHolidays,
    required DateTime anchor,
    String? goalId,
    DateTime? now,
  }) {
    if (rule.frequency == RecurrenceFrequency.none) return null;

    final anchorDay = _dateOnly(anchor);
    DateTime? candidate;
    DateTime? upperBound;

    if (scheduling.mode == SchedulingMode.fixed) {
      final base = rule.nextAfter(anchorDay);
      if (base == null) return null;
      candidate = _dateOnly(base);
      // fixed 模式下没有"窗口"概念，仅用 endDate 作为唯一上界。
      upperBound = rule.endDate == null ? null : _dateOnly(rule.endDate!);
    } else {
      // random 模式：计算 [lower, upper]
      final minGap = (scheduling.randomMinGapDays ?? 1).clamp(1, 365);
      final lower = anchorDay.add(Duration(days: minGap));
      upperBound = _randomUpperBound(rule, anchorDay);
      if (upperBound.isBefore(lower)) return null;
      final seed = _stableSeed(goalId ?? '', _yearWeek(lower));
      candidate = _uniformRandomDayIn(lower, upperBound, seed);
    }

    // skipHolidays：遇节假日前推一天；若越过 upperBound 则回落。
    if (skipHolidays) {
      final upper = upperBound;
      while (HolidayCalendar.isHoliday(candidate!)) {
        final next = candidate.add(const Duration(days: 1));
        if (upper != null && next.isAfter(upper)) {
          // 回落：从 upper 往前找第一个非节假日
          DateTime cur = upper;
          while (cur.isAfter(anchorDay) && HolidayCalendar.isHoliday(cur)) {
            cur = cur.subtract(const Duration(days: 1));
          }
          if (HolidayCalendar.isHoliday(cur)) return null; // 全窗口节假日
          candidate = cur;
          break;
        }
        candidate = next;
      }
    }

    if (rule.endDate != null && candidate.isAfter(_dateOnly(rule.endDate!))) {
      return null;
    }
    return candidate;
  }

  /// 枚举 [start, end] 区间内所有触发日（含端点），用于日历展示。
  static List<DateTime> enumerateOccurrences({
    required RecurrenceRule rule,
    required GoalScheduling scheduling,
    required bool skipHolidays,
    required DateTime start,
    required DateTime end,
    String? goalId,
  }) {
    if (rule.frequency == RecurrenceFrequency.none) return const <DateTime>[];
    final results = <DateTime>[];
    DateTime cursor = _dateOnly(start).subtract(const Duration(days: 1));
    final endDay = _dateOnly(end);
    int safety = 0;
    const maxIterations = 366;
    while (safety++ < maxIterations) {
      final nxt = nextOccurrence(
        rule: rule,
        scheduling: scheduling,
        skipHolidays: skipHolidays,
        anchor: cursor,
        goalId: goalId,
      );
      if (nxt == null) break;
      if (nxt.isAfter(endDay)) break;
      results.add(nxt);
      cursor = nxt;
    }
    return results;
  }

  /// 今日派发：对 `active` 的 goals 应用 recurrence + scheduling + skipHolidays，
  /// 把当日命中的 goal 交给 [onHit] 回调（Task 22.2 / Req 11.8）。
  ///
  /// 调用方：`CompletionVisibilityPolicy.runDailyRollover` 在 step 3 中调用，
  /// `onHit` 通常会转交给 `ReminderScheduler.syncGoals` 的下一次调度。
  static void materializeTodayFromRecurring({
    required Iterable<GoalItem> goals,
    required DateTime today,
    required GoalOccurrenceCallback onHit,
  }) {
    final todayDay = _dateOnly(today);
    for (final g in goals) {
      if (g.status != GoalStatus.active) continue;
      if (g.recurrence.frequency == RecurrenceFrequency.none) continue;
      final effectiveStart = _dateOnly(g.startDate ?? g.createdAt);
      final searchFrom = effectiveStart.isAfter(todayDay)
          ? effectiveStart
          : todayDay;
      final anchor = searchFrom.subtract(const Duration(days: 1));
      final nxt = nextOccurrence(
        rule: g.recurrence,
        scheduling: g.scheduling,
        skipHolidays: g.skipHolidays,
        anchor: anchor,
        goalId: g.id,
        now: today,
      );
      if (nxt == null) continue;
      if (nxt.isAtSameMomentAs(todayDay)) {
        onHit(g, nxt);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime _randomUpperBound(RecurrenceRule rule, DateTime anchor) {
    final interval = rule.interval.clamp(1, 52);
    switch (rule.frequency) {
      case RecurrenceFrequency.daily:
        return anchor.add(Duration(days: interval));
      case RecurrenceFrequency.weekly:
        return anchor.add(Duration(days: 7 * interval));
      case RecurrenceFrequency.monthly:
        final target = DateTime(anchor.year, anchor.month + interval + 1, 0);
        return _dateOnly(target);
      case RecurrenceFrequency.yearly:
        return DateTime(anchor.year + interval, anchor.month, anchor.day);
      case RecurrenceFrequency.none:
        return anchor;
    }
  }

  /// 稳定种子：同一个 goal 在同一 `year-week` 内多次计算得到相同随机日。
  static int _stableSeed(String goalId, int yearWeek) {
    int h = 2166136261;
    for (final c in goalId.codeUnits) {
      h = (h ^ c) & 0x7fffffff;
      h = (h * 16777619) & 0x7fffffff;
    }
    return (h ^ yearWeek) & 0x7fffffff;
  }

  /// `year * 100 + isoWeek` 的简单聚合。
  static int _yearWeek(DateTime d) {
    // 近似 ISO-week：以周一为起点。
    final jan1 = DateTime(d.year, 1, 1);
    final daysSince = _dateOnly(d).difference(jan1).inDays;
    final firstMonday = 1 - jan1.weekday; // 可能为负
    final week = ((daysSince - firstMonday) ~/ 7) + 1;
    return d.year * 100 + week;
  }

  /// 在 `[lower, upper]` 闭区间内用 LCG 选一天。
  static DateTime _uniformRandomDayIn(
    DateTime lower,
    DateTime upper,
    int seed,
  ) {
    final span = upper.difference(lower).inDays;
    if (span <= 0) return lower;
    // 简化版 LCG：ax + c mod 2^31
    var x = seed & 0x7fffffff;
    x = (x * 1103515245 + 12345) & 0x7fffffff;
    final offset = x % (span + 1);
    return lower.add(Duration(days: offset));
  }
}
