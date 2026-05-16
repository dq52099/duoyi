import 'package:flutter_test/flutter_test.dart';

import 'package:duoyi/services/holiday_calendar.dart';

void main() {
  group('HolidayCalendar 2024-2026 内置数据', () {
    test('2024 元旦 / 春节 / 国庆是节假日', () {
      expect(HolidayCalendar.isHoliday(DateTime(2024, 1, 1)), isTrue);
      expect(HolidayCalendar.isHoliday(DateTime(2024, 2, 10)), isTrue);
      expect(HolidayCalendar.isHoliday(DateTime(2024, 10, 1)), isTrue);
    });

    test('2025 元旦 / 春节 / 国庆是节假日', () {
      expect(HolidayCalendar.isHoliday(DateTime(2025, 1, 1)), isTrue);
      expect(HolidayCalendar.isHoliday(DateTime(2025, 1, 28)), isTrue);
      expect(HolidayCalendar.isHoliday(DateTime(2025, 10, 1)), isTrue);
    });

    test('2026 元旦 / 春节 / 国庆是节假日', () {
      expect(HolidayCalendar.isHoliday(DateTime(2026, 1, 1)), isTrue);
      expect(HolidayCalendar.isHoliday(DateTime(2026, 2, 17)), isTrue);
      expect(HolidayCalendar.isHoliday(DateTime(2026, 10, 1)), isTrue);
    });

    test('2026 调休上班日识别正确', () {
      expect(HolidayCalendar.isWorkMakeupDay(DateTime(2026, 2, 15)), isTrue);
      expect(HolidayCalendar.isWorkMakeupDay(DateTime(2026, 9, 27)), isTrue);
    });

    test('未列入的日期不是节假日', () {
      expect(HolidayCalendar.isHoliday(DateTime(2026, 7, 15)), isFalse);
      expect(HolidayCalendar.isWorkMakeupDay(DateTime(2026, 7, 15)), isFalse);
    });

    test('2027 未来年份默认不是节假日（待 updateFrom 注入）', () {
      expect(HolidayCalendar.isHoliday(DateTime(2027, 1, 1)), isFalse);
    });

    test('updateFrom 注入新年份数据后生效', () {
      HolidayCalendar.resetOverrides();
      HolidayCalendar.updateFrom(
        2027,
        const HolidayYear(
          holidays: {'01-01'},
          workMakeupDays: {'01-04'},
        ),
      );
      expect(HolidayCalendar.isHoliday(DateTime(2027, 1, 1)), isTrue);
      expect(HolidayCalendar.isWorkMakeupDay(DateTime(2027, 1, 4)), isTrue);
      HolidayCalendar.resetOverrides();
      expect(HolidayCalendar.isHoliday(DateTime(2027, 1, 1)), isFalse);
    });
  });
}
