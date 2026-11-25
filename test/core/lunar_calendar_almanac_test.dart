import 'package:test/test.dart';

import 'package:duoyi/core/almanac_locale_format.dart';
import 'package:duoyi/core/almanac_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/lunar_calendar.dart';
import 'package:duoyi/services/almanac_tools_service.dart';
import 'package:duoyi/services/holiday_calendar.dart';

void main() {
  tearDown(() {
    HolidayCalendar.resetOverrides();
    I18n.setLocale(AppLocale.zh);
  });

  group('LunarCalendar P1/P2 核心历法与黄历扩展', () {
    test('P1 神煞方位与建除值神字段由 lunar 库真实填充', () {
      final detail = LunarCalendar.almanacDetail(DateTime(2026, 6, 3));

      expect(detail.jiShen, isNotEmpty);
      expect(detail.xiongSha, isNotEmpty);
      expect(detail.caiShenPosition, isNotEmpty);
      expect(detail.xiShenPosition, isNotEmpty);
      expect(detail.fuShenPosition, isNotEmpty);
      expect(detail.yangGuiPosition, isNotEmpty);
      expect(detail.yinGuiPosition, isNotEmpty);
      expect(detail.tianShen, isNotEmpty);
      expect(detail.tianShenType, anyOf('黄道', '黑道'));
      expect(detail.tianShenLuck, anyOf('吉', '凶'));
      expect(detail.zhiXing, '平');
      expect(detail.dayNaYin, '大驿土');
      expect(detail.dayChongShengXiao, '虎');
      expect(detail.yearZodiac, '马');
    });

    test('P1 十二时辰详版包含时辰宜忌、方位、冲煞与纳音', () {
      final hours = LunarCalendar.hourFortunes(DateTime(2026, 6, 3));
      expect(hours, hasLength(12));
      for (final h in hours) {
        expect(h.yi, isNotEmpty);
        expect(h.ji, isNotEmpty);
        expect(h.caiPosition, isNotEmpty);
        expect(h.xiPosition, isNotEmpty);
        expect(h.fuPosition, isNotEmpty);
        expect(h.chongSha, contains('冲'));
        expect(h.chongSha, contains('煞'));
        expect(h.tianShenType, anyOf('黄道', '黑道'));
        expect(h.naYin, isNotEmpty);
      }
    });

    test('P1 物候民俗（数九/三伏/七十二候/月相）、星座、ISO周数与24节气精确时刻', () {
      final winter = LunarCalendar.almanacDetail(DateTime(2026, 1, 10));
      expect(winter.shuJiu, isNotNull);
      expect(winter.shuJiu, contains('九'));

      final summer = LunarCalendar.almanacDetail(DateTime(2026, 7, 25));
      expect(summer.sanFu, isNotNull);
      expect(summer.sanFu, contains('伏'));

      final spring = LunarCalendar.almanacDetail(DateTime(2026, 6, 3));
      expect(spring.wuHou, isNotEmpty);
      expect(spring.hou, isNotEmpty);
      expect(spring.yueXiang, isNotEmpty);
      expect(spring.xingZuo, '双子');
      expect(spring.isoWeekNumber, 23);
      expect(spring.dayOfYear, 154);

      expect(LunarCalendar.isoWeekNumber(DateTime(2026, 1, 1)), 1);
      expect(LunarCalendar.isoWeekNumber(DateTime(2021, 1, 1)), 53);

      final terms2026 = LunarCalendar.yearSolarTerms(2026);
      expect(terms2026, hasLength(24));
      expect(terms2026.first.name, '小寒');
      expect(terms2026.last.name, '冬至');
      for (var i = 1; i < terms2026.length; i++) {
        expect(
          terms2026[i].exactDateTime.isAfter(terms2026[i - 1].exactDateTime),
          isTrue,
        );
      }

      final nextTerm = LunarCalendar.nextSolarTerm(DateTime(2026, 6, 3, 10, 0));
      expect(nextTerm, isNotNull);
      expect(nextTerm!.name, '芒种');
      expect(nextTerm.exactDateTime.year, 2026);
      expect(nextTerm.exactDateTime.month, 6);
      expect(nextTerm.exactDateTime.day, 5);
      expect(nextTerm.remaining.inMinutes, greaterThan(0));
    });

    test('扩展节日合并母亲节、父亲节、感恩节与寒食节且不破坏原有断言', () {
      expect(LunarCalendar.solarFestival(DateTime(2026, 1, 1)), '元旦');
      expect(LunarCalendar.solarFestival(DateTime(2026, 10, 24)), isNull);
      // 2026-05-10 母亲节（五月第二个周日）
      expect(LunarCalendar.solarFestival(DateTime(2026, 5, 10)), '母亲节');
      // 2026-06-21 父亲节（六月第三个周日）
      expect(LunarCalendar.solarFestival(DateTime(2026, 6, 21)), '父亲节');
      // 2026-11-26 感恩节（十一月第四个周四）
      expect(LunarCalendar.solarFestival(DateTime(2026, 11, 26)), '感恩节');
      // 2026-04-04 清明前一日为寒食节
      final hanshi = LunarCalendar.fromSolar(DateTime(2026, 4, 4));
      expect(LunarCalendar.lunarFestival(hanshi), '寒食节');
    });

    test('闰月查询、天数计算与互转完整支持', () {
      expect(LunarCalendar.leapMonthOfLunarYear(2023), 2);
      expect(LunarCalendar.leapMonthOfLunarYear(2025), 6);
      expect(LunarCalendar.leapMonthOfLunarYear(2026), 0);

      expect(LunarCalendar.daysInLunarMonth(2023, 2, isLeap: true), 29);
      expect(LunarCalendar.daysInLunarMonth(2026, 2, isLeap: true), 0);

      expect(
        LunarCalendar.lunarToSolar(2023, 2, 1, isLeap: true),
        DateTime(2023, 3, 22),
      );
      expect(LunarCalendar.tryToSolar(2026, 2, 1, isLeap: true), isNull);
    });

    test('生辰八字简排准确输出四柱、五行统计与纳音', () {
      final ec = LunarCalendar.eightChar(DateTime(2026, 6, 3, 14, 30));
      expect(ec.fourPillars, hasLength(4));
      expect(ec.yearGanZhi, '丙午');
      expect(ec.monthGanZhi, '癸巳');
      expect(ec.dayGanZhi, '戊申');
      expect(ec.timeGanZhi, '己未');
      expect(ec.zodiac, '马');
      expect(ec.dayMaster, '戊');
      expect(ec.dayMasterWuXing, '土');
      final totalElements = ec.wuXingCounts.values.fold<int>(0, (a, b) => a + b);
      expect(totalElements, 8);
      expect(ec.naYin, contains('大驿土'));
    });
  });

  group('AlmanacToolsService 工具箱测试', () {
    test('择吉日查询支持事项别名、仅周末/节假日过滤与避开冲生肖', () {
      final allMarriage = AlmanacToolsService.findAuspiciousDays(
        activity: '结婚',
        startDate: DateTime(2026, 6, 1),
        rangeDays: 60,
      );
      expect(allMarriage, isNotEmpty);
      for (final match in allMarriage) {
        expect(match.suitableTerms, contains('嫁娶'));
        expect(match.avoidTerms, isNot(contains('嫁娶')));
      }

      final restAndAvoidTiger = AlmanacToolsService.findAuspiciousDays(
        activity: '入宅/搬家',
        startDate: DateTime(2026, 6, 1),
        rangeDays: 90,
        weekendsOrHolidaysOnly: true,
        avoidZodiac: '虎',
      );
      for (final match in restAndAvoidTiger) {
        expect(match.isRestDay, isTrue);
        expect(match.dayChongShengXiao, isNot('虎'));
      }
    });

    test('日期间隔计算精确结合法定假日与调休补班', () {
      // 2026-09-20 (周日补班) 到 2026-09-28 (共 8 天 span: 20,21,22,23,24,25,26,27)
      // 20(补班工作), 21..24(周一至周四工作), 25..27(中秋放假) -> 5 工作日, 3 假日, 1 补班, 3 周末日(20,26,27)
      final interval = AlmanacToolsService.calculateDateInterval(
        DateTime(2026, 9, 20),
        DateTime(2026, 9, 28),
      );
      expect(interval.calendarDays, 8);
      expect(interval.workdays, 5);
      expect(interval.holidayDays, 3);
      expect(interval.makeupWorkdays, 1);
      expect(interval.weekendDays, 3);
      expect(interval.restDays, 3);

      final reversed = AlmanacToolsService.calculateDateInterval(
        DateTime(2026, 9, 28),
        DateTime(2026, 9, 20),
      );
      expect(reversed.isReversed, isTrue);
      expect(reversed.signedCalendarDays, -8);
      expect(reversed.calendarDays, 8);
      expect(reversed.workdays, 5);
    });

    test('日期加减推算支持自然日与工作日模式', () {
      final cal = AlmanacToolsService.offsetDate(DateTime(2026, 9, 24), 5);
      expect(cal.targetDate, DateTime(2026, 9, 29));

      // 2026-09-24 (周四) 往后 1 个工作日应跳过 9/25..27 中秋假期 -> 9/28 (周一)
      final work = AlmanacToolsService.offsetDate(
        DateTime(2026, 9, 24),
        1,
        workdaysOnly: true,
      );
      expect(work.targetDate, DateTime(2026, 9, 28));
      expect(work.isWorkday, isTrue);
    });

    test('公农历互转详情正确处理闰月与非法输入', () {
      final solar2Lunar = AlmanacToolsService.solarToLunarDetail(
        DateTime(2023, 3, 22),
      );
      expect(solar2Lunar, isNotNull);
      expect(solar2Lunar!.lunarDate.isLeapMonth, isTrue);
      expect(solar2Lunar.lunarLabel, '闰二月初一');

      final lunar2Solar = AlmanacToolsService.lunarToSolarDetail(
        2023,
        2,
        1,
        isLeap: true,
      );
      expect(lunar2Solar, isNotNull);
      expect(lunar2Solar!.solarDate, DateTime(2023, 3, 22));

      expect(
        AlmanacToolsService.lunarToSolarDetail(2026, 2, 1, isLeap: true),
        isNull,
      );
    });

    test('宜忌白话词典覆盖 100+ 常见词条且中英文均无遗漏', () {
      const sampleTerms = [
        '祭祀', '祈福', '嫁娶', '入宅', '移徙', '开市', '动土', '修造',
        '安床', '出行', '交易', '买车', '纳财', '理发', '求医', '治病',
        '订盟', '纳采', '会亲友', '扫舍', '立券', '赴任', '破土', '安葬',
      ];
      for (final term in sampleTerms) {
        final zh = AlmanacToolsService.explainAlmanacTerm(term);
        final en = AlmanacToolsService.explainAlmanacTerm(term, english: true);
        expect(zh.isKnown, isTrue, reason: '$term should be in plain dictionary');
        expect(zh.explanation, isNotEmpty);
        expect(en.explanation, isNotEmpty);
        expect(en.englishTitle, isNot(matches(RegExp(r'[\u3400-\u9fff]'))));
        expect(en.explanation, isNot(matches(RegExp(r'[\u3400-\u9fff]'))));
      }
    });
  });

  group('AlmanacLocaleFormat & AlmanacUiCopy 英文国际化完整度', () {
    test('英文模式下黄历拓展字段格式化无中文残留', () {
      final cjk = RegExp(r'[\u3400-\u9fff]');
      final detail = LunarCalendar.almanacDetail(DateTime(2026, 6, 3));

      final checks = <String>[
        AlmanacLocaleFormat.formatGanzhiLine(detail, AppLocale.en),
        AlmanacLocaleFormat.formatXingZuo(detail.xingZuo, AppLocale.en),
        AlmanacLocaleFormat.formatTianShen(detail.tianShen, AppLocale.en),
        AlmanacLocaleFormat.formatTianShenType(detail.tianShenType, AppLocale.en),
        AlmanacLocaleFormat.formatTianShenLuck(detail.tianShenLuck, AppLocale.en),
        AlmanacLocaleFormat.formatZhiXing(detail.zhiXing, AppLocale.en),
        AlmanacLocaleFormat.formatDirection(detail.caiShenPosition, AppLocale.en),
        AlmanacLocaleFormat.formatDirection(detail.xiShenPosition, AppLocale.en),
        AlmanacLocaleFormat.formatDirection(detail.fuShenPosition, AppLocale.en),
        AlmanacLocaleFormat.formatYueXiang(detail.yueXiang, AppLocale.en),
        AlmanacLocaleFormat.formatWuHou(detail.wuHou, AppLocale.en),
        AlmanacLocaleFormat.formatHou(detail.hou, AppLocale.en),
        AlmanacLocaleFormat.formatFiveElements(
          detail.fiveElements,
          dayNaYin: detail.dayNaYin,
          zhiXing: detail.zhiXing,
          locale: AppLocale.en,
        ),
        AlmanacLocaleFormat.formatClash(detail, AppLocale.en),
        AlmanacLocaleFormat.formatMansion(detail.mansion, AppLocale.en),
        AlmanacLocaleFormat.formatFetalGod(detail.fetalGod, AppLocale.en),
        AlmanacLocaleFormat.formatPengZu(detail.pengZu, AppLocale.en),
        ...AlmanacLocaleFormat.formatShenShaList(detail.jiShen, AppLocale.en),
        ...AlmanacLocaleFormat.formatShenShaList(detail.xiongSha, AppLocale.en),
        AlmanacLocaleFormat.formatFestival('母亲节', AppLocale.en)!,
        AlmanacLocaleFormat.formatFestival('寒食节', AppLocale.en)!,
        AlmanacLocaleFormat.formatShuJiu('一九第3天', AppLocale.en)!,
        AlmanacLocaleFormat.formatSanFu('初伏第1天', AppLocale.en)!,
      ];

      for (final text in checks) {
        expect(text, isNotEmpty);
        expect(text, isNot(matches(cjk)), reason: 'Unexpected CJK in "$text"');
      }

      I18n.setLocale(AppLocale.en);
      expect(
        AlmanacUiCopy.solarTermCountdownText(detail.nextSolarTerm!, AppLocale.en),
        isNot(matches(cjk)),
      );
      expect(
        AlmanacUiCopy.isoWeekBadge(detail.isoWeekNumber, AppLocale.en),
        'W23',
      );
    });
  });
}
