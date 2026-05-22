import 'package:duoyi/core/report_reminder_config.dart';
import 'package:test/test.dart';

void main() {
  group('ReportReminderConfig', () {
    test('keeps the legacy weekly default at Monday 09:00', () {
      const config = ReportReminderConfig(enabled: true);

      expect(
        config.nextWeeklyReminderTime(DateTime(2026, 5, 20, 8, 0)),
        DateTime(2026, 5, 25, 9, 0),
      );
      expect(
        config.nextWeeklyReminderTime(DateTime(2026, 5, 25, 9, 0)),
        DateTime(2026, 6, 1, 9, 0),
      );
    });

    test('supports daily report reminder time', () {
      const config = ReportReminderConfig(enabled: true, hour: 21, minute: 30);

      expect(
        config.nextDailyReminderTime(DateTime(2026, 5, 21, 8, 0)),
        DateTime(2026, 5, 21, 21, 30),
      );
      expect(
        config.nextDailyReminderTime(DateTime(2026, 5, 21, 21, 30)),
        DateTime(2026, 5, 22, 21, 30),
      );
    });

    test('supports custom weekly weekday and time', () {
      const config = ReportReminderConfig(
        enabled: true,
        weekday: DateTime.friday,
        hour: 18,
        minute: 30,
      );

      expect(
        config.nextWeeklyReminderTime(DateTime(2026, 5, 20, 8, 0)),
        DateTime(2026, 5, 22, 18, 30),
      );
      expect(
        config.nextWeeklyReminderTime(DateTime(2026, 5, 22, 18, 30)),
        DateTime(2026, 5, 29, 18, 30),
      );
    });

    test('supports custom monthly day and clamps short months', () {
      const config = ReportReminderConfig(
        enabled: true,
        monthDay: 31,
        hour: 8,
        minute: 15,
      );

      expect(
        config.nextMonthlyReminderTime(DateTime(2026, 1, 20, 12, 0)),
        DateTime(2026, 1, 31, 8, 15),
      );
      expect(
        config.nextMonthlyReminderTime(DateTime(2026, 1, 31, 8, 15)),
        DateTime(2026, 2, 28, 8, 15),
      );
      expect(
        ReportReminderConfig.monthlyReminderDate(2026, 4, 31, 9, 0),
        DateTime(2026, 4, 30, 9, 0),
      );
    });

    test('supports custom yearly month day and clamps invalid dates', () {
      const config = ReportReminderConfig(
        enabled: true,
        month: 2,
        monthDay: 29,
        hour: 7,
        minute: 45,
      );

      expect(
        config.nextYearlyReminderTime(DateTime(2026, 1, 20, 12, 0)),
        DateTime(2026, 2, 28, 7, 45),
      );
      expect(
        config.nextYearlyReminderTime(DateTime(2026, 2, 28, 7, 45)),
        DateTime(2027, 2, 28, 7, 45),
      );
      expect(
        config.nextYearlyReminderTime(DateTime(2027, 3, 1, 8, 0)),
        DateTime(2028, 2, 29, 7, 45),
      );
      expect(
        ReportReminderConfig.yearlyReminderDate(2026, 13, 31, 9, 0),
        DateTime(2026, 12, 31, 9, 0),
      );
    });

    test('clamps invalid copied values into valid ranges', () {
      final config = const ReportReminderConfig().copyWith(
        hour: 99,
        minute: -5,
        weekday: 10,
        month: 13,
        monthDay: 0,
      );

      expect(config.hour, 23);
      expect(config.minute, 0);
      expect(config.weekday, 7);
      expect(config.month, 12);
      expect(config.monthDay, 1);
    });
  });
}
