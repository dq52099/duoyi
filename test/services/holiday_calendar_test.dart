import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/services/holiday_calendar.dart';

void main() {
  tearDown(() {
    HolidayCalendar.resetOverrides();
    I18n.setLocale(AppLocale.zh);
  });

  group('HolidayCalendar 2024-2027 内置数据与修复', () {
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

    test('2026 元旦 / 春节 / 国庆是节假日，且修复 2026-09-27 冲突', () {
      expect(HolidayCalendar.isHoliday(DateTime(2026, 1, 1)), isTrue);
      expect(HolidayCalendar.isHoliday(DateTime(2026, 2, 17)), isTrue);
      expect(HolidayCalendar.isHoliday(DateTime(2026, 10, 1)), isTrue);

      expect(HolidayCalendar.isWorkMakeupDay(DateTime(2026, 2, 15)), isTrue);
      // 2026-09-20 为中秋节前调休补班日；2026-09-25..27 为中秋放假，不再误判为补班
      expect(HolidayCalendar.isWorkMakeupDay(DateTime(2026, 9, 20)), isTrue);
      expect(HolidayCalendar.isHoliday(DateTime(2026, 9, 20)), isFalse);
      expect(HolidayCalendar.isHoliday(DateTime(2026, 9, 25)), isTrue);
      expect(HolidayCalendar.isHoliday(DateTime(2026, 9, 26)), isTrue);
      expect(HolidayCalendar.isHoliday(DateTime(2026, 9, 27)), isTrue);
      expect(HolidayCalendar.isWorkMakeupDay(DateTime(2026, 9, 27)), isFalse);
    });

    test('2027 完整法定节假日与调休补班识别正确', () {
      // 元旦 1/1-1/3
      expect(HolidayCalendar.isHoliday(DateTime(2027, 1, 1)), isTrue);
      expect(HolidayCalendar.isHoliday(DateTime(2027, 1, 3)), isTrue);
      // 春节 2/5-2/13，补班 1/31 & 2/14
      expect(HolidayCalendar.isWorkMakeupDay(DateTime(2027, 1, 31)), isTrue);
      expect(HolidayCalendar.isHoliday(DateTime(2027, 2, 5)), isTrue);
      expect(HolidayCalendar.isHoliday(DateTime(2027, 2, 13)), isTrue);
      expect(HolidayCalendar.isWorkMakeupDay(DateTime(2027, 2, 14)), isTrue);
      // 清明 4/3-4/5，劳动节 5/1-5/5 + 5/8 补班，端午 6/9，中秋 9/15
      expect(HolidayCalendar.isHoliday(DateTime(2027, 4, 5)), isTrue);
      expect(HolidayCalendar.isHoliday(DateTime(2027, 5, 3)), isTrue);
      expect(HolidayCalendar.isWorkMakeupDay(DateTime(2027, 5, 8)), isTrue);
      expect(HolidayCalendar.isHoliday(DateTime(2027, 6, 9)), isTrue);
      expect(HolidayCalendar.isHoliday(DateTime(2027, 9, 15)), isTrue);
      // 国庆 10/1-10/7，补班 9/26 & 10/9
      expect(HolidayCalendar.isWorkMakeupDay(DateTime(2027, 9, 26)), isTrue);
      expect(HolidayCalendar.isHoliday(DateTime(2027, 10, 1)), isTrue);
      expect(HolidayCalendar.isHoliday(DateTime(2027, 10, 7)), isTrue);
      expect(HolidayCalendar.isWorkMakeupDay(DateTime(2027, 10, 9)), isTrue);
    });

    test('未列入的普通日期不是节假日，工作日与休息日判定准确', () {
      expect(HolidayCalendar.isHoliday(DateTime(2026, 7, 15)), isFalse);
      expect(HolidayCalendar.isWorkMakeupDay(DateTime(2026, 7, 15)), isFalse);
      expect(HolidayCalendar.isWorkday(DateTime(2026, 7, 15)), isTrue);
      expect(HolidayCalendar.isRestDay(DateTime(2026, 7, 18)), isTrue);
      expect(HolidayCalendar.isWorkday(DateTime(2027, 1, 31)), isTrue);
      expect(HolidayCalendar.isWorkday(DateTime(2027, 2, 5)), isFalse);
    });

    test('内置之外的历史年份支持 lunar HolidayUtil 回退', () {
      expect(HolidayCalendar.isHoliday(DateTime(2023, 10, 1)), isTrue);
      expect(HolidayCalendar.isWorkMakeupDay(DateTime(2023, 10, 7)), isTrue);
      expect(HolidayCalendar.holidayName(DateTime(2023, 10, 1)), '国庆节');
      final schedules2023 = HolidayCalendar.schedulesForYear(2023);
      expect(schedules2023, isNotEmpty);
    });

    test('未排期远期年份默认非节假日，支持 updateFrom 与 resetOverrides', () {
      expect(HolidayCalendar.isHoliday(DateTime(2035, 1, 1)), isFalse);
      HolidayCalendar.updateFrom(
        2035,
        const HolidayYear(holidays: {'01-01'}, workMakeupDays: {'01-06'}),
      );
      expect(HolidayCalendar.isHoliday(DateTime(2035, 1, 1)), isTrue);
      expect(HolidayCalendar.isWorkMakeupDay(DateTime(2035, 1, 6)), isTrue);
      HolidayCalendar.resetOverrides();
      expect(HolidayCalendar.isHoliday(DateTime(2035, 1, 1)), isFalse);
    });

    test('schedulesForYear 与 upcomingHolidays 返回结构化放假安排与倒计时', () {
      for (final y in [2024, 2025, 2026, 2027]) {
        final schedules = HolidayCalendar.schedulesForYear(y);
        expect(schedules.length, greaterThanOrEqualTo(6));
        for (final item in schedules) {
          expect(item.totalDays, item.holidayDates.length);
          expect(item.bridgeLeaveTip, isNotEmpty);
          expect(item.bridgeLeaveTipEn, isNotEmpty);
        }
      }

      final upcoming = HolidayCalendar.upcomingHolidays(
        DateTime(2026, 11, 23),
        limit: 3,
      );
      expect(upcoming, hasLength(3));
      expect(upcoming.first.year, 2027);
      expect(upcoming.first.name, '元旦');
      expect(upcoming.first.daysUntil(DateTime(2026, 11, 23)), 39);
      expect(
        upcoming[1].daysUntil(DateTime(2027, 2, 7)),
        0,
        reason: '正在假期中倒计时应为 0',
      );
    });

    test('refreshYearFromRemote 离线安全且支持标准 JSON 注入', () async {
      expect(await HolidayCalendar.refreshYearFromRemote(2035), isFalse);

      final failingClient = MockClient(
        (_) async => http.Response('error', 503),
      );
      expect(
        await HolidayCalendar.refreshYearFromRemote(
          2035,
          baseUrl: 'https://example.invalid',
          client: failingClient,
        ),
        isFalse,
      );
      expect(HolidayCalendar.isHoliday(DateTime(2035, 1, 1)), isFalse);

      final okClient = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'holidays': ['01-01', '01-02'],
            'work_makeup_days': ['01-05'],
          }),
          200,
        ),
      );
      expect(
        await HolidayCalendar.refreshYearFromRemote(
          2035,
          baseUrl: 'https://example.invalid/',
          client: okClient,
        ),
        isTrue,
      );
      expect(HolidayCalendar.isHoliday(DateTime(2035, 1, 2)), isTrue);
      expect(HolidayCalendar.isWorkMakeupDay(DateTime(2035, 1, 5)), isTrue);
    });
  });
}
