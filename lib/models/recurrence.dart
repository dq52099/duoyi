/// 重复规则：配合 TodoItem / Habit / Anniversary 使用。
/// 支持 日/周/月/年 四种频次 + 间隔 + 结束日期/次数。
enum RecurrenceFrequency { none, daily, weekly, monthly, yearly }

class RecurrenceRule {
  final RecurrenceFrequency frequency;
  final int interval; // 每 N 个周期
  final List<int>? byWeekdays; // weekly: 0=周一 .. 6=周日
  final int? byMonthDay; // monthly: 1..31
  final DateTime? endDate; // 结束日期 (含)
  final int? maxOccurrences; // 最多产生 N 次

  const RecurrenceRule({
    this.frequency = RecurrenceFrequency.none,
    this.interval = 1,
    this.byWeekdays,
    this.byMonthDay,
    this.endDate,
    this.maxOccurrences,
  });

  bool get isActive => frequency != RecurrenceFrequency.none;

  /// 给定"上一次执行/生成"的日期，返回下一次日期；无则返回 null。
  DateTime? nextAfter(DateTime reference) {
    if (!isActive) return null;
    DateTime next;
    switch (frequency) {
      case RecurrenceFrequency.daily:
        next = reference.add(Duration(days: interval));
        break;
      case RecurrenceFrequency.weekly:
        if (byWeekdays != null && byWeekdays!.isNotEmpty) {
          // 找到 reference 之后最近的一个匹配 weekday
          final sorted = [...byWeekdays!]..sort();
          for (int add = 1; add <= 7 * interval; add++) {
            final cand = reference.add(Duration(days: add));
            if (sorted.contains(cand.weekday - 1)) return cand;
          }
          next = reference.add(Duration(days: 7 * interval));
        } else {
          next = reference.add(Duration(days: 7 * interval));
        }
        break;
      case RecurrenceFrequency.monthly:
        final m = reference.month + interval;
        final targetYear = reference.year + (m - 1) ~/ 12;
        final targetMonth = ((m - 1) % 12) + 1;
        final day =
            byMonthDay ?? reference.day;
        final lastDayOfTarget =
            DateTime(targetYear, targetMonth + 1, 0).day;
        next = DateTime(
          targetYear,
          targetMonth,
          day > lastDayOfTarget ? lastDayOfTarget : day,
        );
        break;
      case RecurrenceFrequency.yearly:
        final lastDay =
            DateTime(reference.year + interval, reference.month + 1, 0).day;
        next = DateTime(
          reference.year + interval,
          reference.month,
          reference.day > lastDay ? lastDay : reference.day,
        );
        break;
      case RecurrenceFrequency.none:
        return null;
    }
    if (endDate != null && next.isAfter(endDate!)) return null;
    return next;
  }

  String get label {
    final base = switch (frequency) {
      RecurrenceFrequency.none => '不重复',
      RecurrenceFrequency.daily => interval == 1 ? '每天' : '每 $interval 天',
      RecurrenceFrequency.weekly => interval == 1 ? '每周' : '每 $interval 周',
      RecurrenceFrequency.monthly =>
        interval == 1 ? '每月' : '每 $interval 月',
      RecurrenceFrequency.yearly => interval == 1 ? '每年' : '每 $interval 年',
    };
    if (frequency == RecurrenceFrequency.weekly &&
        byWeekdays != null &&
        byWeekdays!.isNotEmpty) {
      const names = ['一', '二', '三', '四', '五', '六', '日'];
      final days = ([...byWeekdays!]..sort()).map((d) => names[d]).join('/');
      return '$base · $days';
    }
    return base;
  }

  Map<String, dynamic> toJson() => {
        'frequency': frequency.index,
        'interval': interval,
        'byWeekdays': byWeekdays,
        'byMonthDay': byMonthDay,
        'endDate': endDate?.toIso8601String(),
        'maxOccurrences': maxOccurrences,
      };

  factory RecurrenceRule.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const RecurrenceRule();
    return RecurrenceRule(
      frequency: RecurrenceFrequency.values[json['frequency'] ?? 0],
      interval: (json['interval'] as num?)?.toInt() ?? 1,
      byWeekdays: (json['byWeekdays'] as List?)?.cast<int>(),
      byMonthDay: (json['byMonthDay'] as num?)?.toInt(),
      endDate: json['endDate'] != null
          ? DateTime.tryParse(json['endDate'].toString())
          : null,
      maxOccurrences: (json['maxOccurrences'] as num?)?.toInt(),
    );
  }

  RecurrenceRule copyWith({
    RecurrenceFrequency? frequency,
    int? interval,
    List<int>? byWeekdays,
    int? byMonthDay,
    DateTime? endDate,
    int? maxOccurrences,
  }) =>
      RecurrenceRule(
        frequency: frequency ?? this.frequency,
        interval: interval ?? this.interval,
        byWeekdays: byWeekdays ?? this.byWeekdays,
        byMonthDay: byMonthDay ?? this.byMonthDay,
        endDate: endDate ?? this.endDate,
        maxOccurrences: maxOccurrences ?? this.maxOccurrences,
      );
}
