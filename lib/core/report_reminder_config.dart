class ReportReminderConfig {
  final bool enabled;
  final int hour;
  final int minute;
  final int weekday;
  final int month;
  final int monthDay;

  const ReportReminderConfig({
    this.enabled = false,
    this.hour = 9,
    this.minute = 0,
    this.weekday = DateTime.monday,
    this.month = 1,
    this.monthDay = 1,
  });

  ReportReminderConfig copyWith({
    bool? enabled,
    int? hour,
    int? minute,
    int? weekday,
    int? month,
    int? monthDay,
  }) {
    return ReportReminderConfig(
      enabled: enabled ?? this.enabled,
      hour: (hour ?? this.hour).clamp(0, 23),
      minute: (minute ?? this.minute).clamp(0, 59),
      weekday: (weekday ?? this.weekday).clamp(1, 7),
      month: (month ?? this.month).clamp(1, 12),
      monthDay: (monthDay ?? this.monthDay).clamp(1, 31),
    );
  }

  DateTime nextWeeklyReminderTime(DateTime now) {
    var target = DateTime(now.year, now.month, now.day, hour, minute);
    final daysUntilTarget = (weekday - target.weekday) % 7;
    target = target.add(Duration(days: daysUntilTarget));
    if (!target.isAfter(now)) target = target.add(const Duration(days: 7));
    return target;
  }

  DateTime nextDailyReminderTime(DateTime now) {
    var target = DateTime(now.year, now.month, now.day, hour, minute);
    if (!target.isAfter(now)) target = target.add(const Duration(days: 1));
    return target;
  }

  DateTime nextMonthlyReminderTime(DateTime now) {
    var target = monthlyReminderDate(
      now.year,
      now.month,
      monthDay,
      hour,
      minute,
    );
    if (!target.isAfter(now)) {
      target = monthlyReminderDate(
        now.year,
        now.month + 1,
        monthDay,
        hour,
        minute,
      );
    }
    return target;
  }

  DateTime nextYearlyReminderTime(DateTime now) {
    var target = yearlyReminderDate(now.year, month, monthDay, hour, minute);
    if (!target.isAfter(now)) {
      target = yearlyReminderDate(now.year + 1, month, monthDay, hour, minute);
    }
    return target;
  }

  static DateTime monthlyReminderDate(
    int year,
    int month,
    int day,
    int hour,
    int minute,
  ) {
    final lastDay = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, day.clamp(1, lastDay), hour, minute);
  }

  static DateTime yearlyReminderDate(
    int year,
    int month,
    int day,
    int hour,
    int minute,
  ) {
    return monthlyReminderDate(year, month.clamp(1, 12), day, hour, minute);
  }
}
