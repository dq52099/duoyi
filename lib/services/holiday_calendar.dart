/// 法定节假日与调休判定服务（Task 21 / Requirements 11.2 + 万年历 P0/P1 升级）。
///
/// 数据策略：
/// - 内置国务院办公厅公布数据（`_kBuiltinHolidays` & `_kBuiltinSchedules`）覆盖 2024–2027。
/// - 超出内置年份范围且未被 [updateFrom] 覆盖的年份，自动回退至 `lunar` 包的
///   [lunar_pkg.HolidayUtil] 历史/官方数据表（2001–2026+）。
/// - 预留 [HolidayCalendar.updateFrom] 与非阻塞离线安全辅助 [refreshYearFromRemote]，
///   供后端 `/api/holidays/{year}` 或本地配置动态注入覆盖。
///
/// 语义：
/// - [isHoliday]：当天是否是**法定放假日**（不管是不是周末）。
/// - [isWorkMakeupDay]：当天是否是**周末调休上班日**（例如春节前后的周末补班）。
/// - [isWorkday]：当天是否需要上班（非法定放假，且为调休上班日或周一至周五）。
/// - [isRestDay]：当天是否休息（法定放假日，或非调休的周六/周日）。
library;

import 'dart:collection';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:lunar/lunar.dart' as lunar_pkg;

import '../core/i18n.dart';

/// 法定节假日 / 调休上班一年的数据集合。
class HolidayYear {
  /// `MM-DD` 字符串集合。
  final Set<String> holidays;

  /// `MM-DD` 字符串集合（周末调休上班）。
  final Set<String> workMakeupDays;

  const HolidayYear({required this.holidays, required this.workMakeupDays});

  factory HolidayYear.fromJson(Map<String, dynamic> json) {
    final rawHolidays = json['holidays'];
    final rawMakeup = json['work_makeup_days'] ?? json['workMakeupDays'];
    return HolidayYear(
      holidays: rawHolidays is Iterable
          ? rawHolidays
                .map((e) => e.toString().trim())
                .where((e) => e.isNotEmpty)
                .toSet()
          : const <String>{},
      workMakeupDays: rawMakeup is Iterable
          ? rawMakeup
                .map((e) => e.toString().trim())
                .where((e) => e.isNotEmpty)
                .toSet()
          : const <String>{},
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'holidays': holidays.toList()..sort(),
    'work_makeup_days': workMakeupDays.toList()..sort(),
  };
}

/// 单个法定节假日安排条目（用于放假安排、拼假建议与倒计时）。
class HolidayScheduleItem {
  final String id;
  final int year;
  final String name;
  final String nameEn;
  final DateTime startDate;
  final DateTime endDate;
  final int totalDays;
  final List<DateTime> holidayDates;
  final List<DateTime> makeupDates;
  final String bridgeLeaveTip;
  final String bridgeLeaveTipEn;

  HolidayScheduleItem({
    required this.id,
    required this.year,
    required this.name,
    required this.nameEn,
    required this.startDate,
    required this.endDate,
    required this.totalDays,
    required List<DateTime> holidayDates,
    required List<DateTime> makeupDates,
    this.bridgeLeaveTip = '',
    this.bridgeLeaveTipEn = '',
  }) : holidayDates = List.unmodifiable(holidayDates),
       makeupDates = List.unmodifiable(makeupDates);

  /// 相对于 [from] 的倒计时天数：
  /// - 正在假期中返回 `0`
  /// - 未开始返回正整数天数
  /// - 已结束返回负数
  int daysUntil(DateTime from) {
    final base = DateTime.utc(from.year, from.month, from.day);
    final start = DateTime.utc(startDate.year, startDate.month, startDate.day);
    final end = DateTime.utc(endDate.year, endDate.month, endDate.day);
    if (!base.isBefore(start) && !base.isAfter(end)) {
      return 0;
    }
    return start.difference(base).inDays;
  }

  bool isOngoingOn(DateTime date) {
    final d = DateTime.utc(date.year, date.month, date.day);
    final start = DateTime.utc(startDate.year, startDate.month, startDate.day);
    final end = DateTime.utc(endDate.year, endDate.month, endDate.day);
    return !d.isBefore(start) && !d.isAfter(end);
  }

  String localizedName([AppLocale? locale]) =>
      (locale ?? I18n.current) == AppLocale.en ? nameEn : name;

  String localizedBridgeLeaveTip([AppLocale? locale]) =>
      (locale ?? I18n.current) == AppLocale.en
      ? bridgeLeaveTipEn
      : bridgeLeaveTip;
}

/// 2024–2027 法定节假日（来源：国务院办公厅公告）。
///
/// 数据为 `MM-DD` 字符串；`year -> HolidayYear`。
const Map<int, HolidayYear> _kBuiltinHolidays = <int, HolidayYear>{
  2024: HolidayYear(
    holidays: <String>{
      // 元旦
      '01-01',
      // 春节
      '02-10', '02-11', '02-12', '02-13', '02-14', '02-15', '02-16', '02-17',
      // 清明
      '04-04', '04-05', '04-06',
      // 劳动节
      '05-01', '05-02', '05-03', '05-04', '05-05',
      // 端午
      '06-10',
      // 中秋
      '09-15', '09-16', '09-17',
      // 国庆
      '10-01', '10-02', '10-03', '10-04', '10-05', '10-06', '10-07',
    },
    workMakeupDays: <String>{
      '02-04',
      '02-18',
      '04-07',
      '04-28',
      '05-11',
      '09-14',
      '09-29',
      '10-12',
    },
  ),
  2025: HolidayYear(
    holidays: <String>{
      '01-01',
      // 春节（2025 春节 1/28–2/4，其中 1/28 除夕）
      '01-28', '01-29', '01-30', '01-31', '02-01', '02-02', '02-03', '02-04',
      // 清明
      '04-04', '04-05', '04-06',
      // 劳动节
      '05-01', '05-02', '05-03', '05-04', '05-05',
      // 端午
      '05-31', '06-01', '06-02',
      // 中秋 + 国庆（连休）
      '10-01', '10-02', '10-03', '10-04', '10-05', '10-06', '10-07', '10-08',
    },
    workMakeupDays: <String>{'01-26', '02-08', '04-27', '09-28', '10-11'},
  ),
  2026: HolidayYear(
    holidays: <String>{
      // 元旦
      '01-01', '01-02', '01-03',
      // 春节（2026 春节 2/17 除夕）
      '02-17', '02-18', '02-19', '02-20', '02-21', '02-22', '02-23',
      // 清明
      '04-05', '04-06', '04-07',
      // 劳动节
      '05-01', '05-02', '05-03', '05-04', '05-05',
      // 端午
      '06-19', '06-20', '06-21',
      // 中秋（09-20 补班，09-25..27 放假）
      '09-25', '09-26', '09-27',
      // 国庆
      '10-01', '10-02', '10-03', '10-04', '10-05', '10-06', '10-07',
    },
    workMakeupDays: <String>{
      '02-15',
      '02-28',
      '04-26',
      '06-28',
      '09-20',
      '10-10',
    },
  ),
  2027: HolidayYear(
    holidays: <String>{
      // 元旦：1月1日（周五）至3日（周日）放假，共3天
      '01-01', '01-02', '01-03',
      // 春节：2月5日（除夕，周五）至13日（正月初八，周六）放假调休，共9天
      '02-05', '02-06', '02-07', '02-08', '02-09',
      '02-10', '02-11', '02-12', '02-13',
      // 清明节：4月3日（周六）至5日（周一）放假，共3天
      '04-03', '04-04', '04-05',
      // 劳动节：5月1日（周六）至5日（周三）放假调休，共5天
      '05-01', '05-02', '05-03', '05-04', '05-05',
      // 端午节：6月9日（周三）放假，共1天
      '06-09',
      // 中秋节：9月15日（周三）放假，共1天
      '09-15',
      // 国庆节：10月1日（周五）至7日（周四）放假调休，共7天
      '10-01', '10-02', '10-03', '10-04', '10-05', '10-06', '10-07',
    },
    workMakeupDays: <String>{
      // 春节调休
      '01-31',
      '02-14',
      // 劳动节调休
      '05-08',
      // 国庆节调休
      '09-26',
      '10-09',
    },
  ),
};

List<DateTime> _dateRange(int year, int month, int startDay, int endDay) => [
  for (int d = startDay; d <= endDay; d++) DateTime(year, month, d),
];

List<DateTime> _datesFromPairs(int year, List<(int, int)> pairs) => [
  for (final (m, d) in pairs) DateTime(year, m, d),
];

final Map<int, List<HolidayScheduleItem>> _kBuiltinSchedules =
    <int, List<HolidayScheduleItem>>{
      2024: <HolidayScheduleItem>[
        HolidayScheduleItem(
          id: '2024-new-year',
          year: 2024,
          name: '元旦',
          nameEn: "New Year's Day",
          startDate: DateTime(2024, 1, 1),
          endDate: DateTime(2024, 1, 1),
          totalDays: 1,
          holidayDates: _datesFromPairs(2024, [(1, 1)]),
          makeupDates: const [],
          bridgeLeaveTip: '与前周末连休 3 天；1月2日至5日请假4天可连休9天',
          bridgeLeaveTipEn:
              '3-day break with prior weekend; take Jan 2–5 off (4 days) for 9 days.',
        ),
        HolidayScheduleItem(
          id: '2024-spring-festival',
          year: 2024,
          name: '春节',
          nameEn: 'Spring Festival',
          startDate: DateTime(2024, 2, 10),
          endDate: DateTime(2024, 2, 17),
          totalDays: 8,
          holidayDates: _dateRange(2024, 2, 10, 17),
          makeupDates: _datesFromPairs(2024, [(2, 4), (2, 18)]),
          bridgeLeaveTip: '2月5日至9日请假5天，或18日请假1天可错峰连休',
          bridgeLeaveTipEn:
              'Take Feb 5–9 off (5 days) or Feb 18 (1 day) to extend the holiday.',
        ),
        HolidayScheduleItem(
          id: '2024-qingming',
          year: 2024,
          name: '清明节',
          nameEn: 'Qingming Festival',
          startDate: DateTime(2024, 4, 4),
          endDate: DateTime(2024, 4, 6),
          totalDays: 3,
          holidayDates: _dateRange(2024, 4, 4, 6),
          makeupDates: _datesFromPairs(2024, [(4, 7)]),
          bridgeLeaveTip: '4月1日至3日请假3天，可拼出8天小长假',
          bridgeLeaveTipEn:
              'Take Apr 1–3 off (3 days) for an 8-day continuous break.',
        ),
        HolidayScheduleItem(
          id: '2024-labor-day',
          year: 2024,
          name: '劳动节',
          nameEn: 'Labor Day',
          startDate: DateTime(2024, 5, 1),
          endDate: DateTime(2024, 5, 5),
          totalDays: 5,
          holidayDates: _dateRange(2024, 5, 1, 5),
          makeupDates: _datesFromPairs(2024, [(4, 28), (5, 11)]),
          bridgeLeaveTip: '4月28日至30日请假3天，可连休9天',
          bridgeLeaveTipEn:
              'Take Apr 28–30 off (3 days) for a 9-day continuous break.',
        ),
        HolidayScheduleItem(
          id: '2024-dragon-boat',
          year: 2024,
          name: '端午节',
          nameEn: 'Dragon Boat Festival',
          startDate: DateTime(2024, 6, 10),
          endDate: DateTime(2024, 6, 10),
          totalDays: 1,
          holidayDates: _datesFromPairs(2024, [(6, 10)]),
          makeupDates: const [],
          bridgeLeaveTip: '与周末连休3天；6月11日至14日请假4天可连休9天',
          bridgeLeaveTipEn:
              '3-day break with weekend; take Jun 11–14 off (4 days) for 9 days.',
        ),
        HolidayScheduleItem(
          id: '2024-mid-autumn',
          year: 2024,
          name: '中秋节',
          nameEn: 'Mid-Autumn Festival',
          startDate: DateTime(2024, 9, 15),
          endDate: DateTime(2024, 9, 17),
          totalDays: 3,
          holidayDates: _dateRange(2024, 9, 15, 17),
          makeupDates: _datesFromPairs(2024, [(9, 14)]),
          bridgeLeaveTip: '9月18日至20日请假3天，可连休8天',
          bridgeLeaveTipEn: 'Take Sep 18–20 off (3 days) for an 8-day break.',
        ),
        HolidayScheduleItem(
          id: '2024-national-day',
          year: 2024,
          name: '国庆节',
          nameEn: 'National Day',
          startDate: DateTime(2024, 10, 1),
          endDate: DateTime(2024, 10, 7),
          totalDays: 7,
          holidayDates: _dateRange(2024, 10, 1, 7),
          makeupDates: _datesFromPairs(2024, [(9, 29), (10, 12)]),
          bridgeLeaveTip: '9月29日至30日请假2天，或10月8日至12日请假可享长假',
          bridgeLeaveTipEn:
              'Take Sep 29–30 off (2 days) for a 10-day break.',
        ),
      ],
      2025: <HolidayScheduleItem>[
        HolidayScheduleItem(
          id: '2025-new-year',
          year: 2025,
          name: '元旦',
          nameEn: "New Year's Day",
          startDate: DateTime(2025, 1, 1),
          endDate: DateTime(2025, 1, 1),
          totalDays: 1,
          holidayDates: _datesFromPairs(2025, [(1, 1)]),
          makeupDates: const [],
          bridgeLeaveTip: '1月2日至3日请假2天，可与周末连休5天',
          bridgeLeaveTipEn:
              'Take Jan 2–3 off (2 days) for a 5-day break with the weekend.',
        ),
        HolidayScheduleItem(
          id: '2025-spring-festival',
          year: 2025,
          name: '春节',
          nameEn: 'Spring Festival',
          startDate: DateTime(2025, 1, 28),
          endDate: DateTime(2025, 2, 4),
          totalDays: 8,
          holidayDates: [
            ..._dateRange(2025, 1, 28, 31),
            ..._dateRange(2025, 2, 1, 4),
          ],
          makeupDates: _datesFromPairs(2025, [(1, 26), (2, 8)]),
          bridgeLeaveTip: '1月26日至27日请假2天，可连休11天',
          bridgeLeaveTipEn:
              'Take Jan 26–27 off (2 days) for an 11-day continuous break.',
        ),
        HolidayScheduleItem(
          id: '2025-qingming',
          year: 2025,
          name: '清明节',
          nameEn: 'Qingming Festival',
          startDate: DateTime(2025, 4, 4),
          endDate: DateTime(2025, 4, 6),
          totalDays: 3,
          holidayDates: _dateRange(2025, 4, 4, 6),
          makeupDates: const [],
          bridgeLeaveTip: '3月31日至4月3日请假4天，可连休9天',
          bridgeLeaveTipEn: 'Take Mar 31–Apr 3 off (4 days) for a 9-day break.',
        ),
        HolidayScheduleItem(
          id: '2025-labor-day',
          year: 2025,
          name: '劳动节',
          nameEn: 'Labor Day',
          startDate: DateTime(2025, 5, 1),
          endDate: DateTime(2025, 5, 5),
          totalDays: 5,
          holidayDates: _dateRange(2025, 5, 1, 5),
          makeupDates: _datesFromPairs(2025, [(4, 27)]),
          bridgeLeaveTip: '4月27日至30日请假4天，可拼出10天长假',
          bridgeLeaveTipEn: 'Take Apr 27–30 off (4 days) for a 10-day break.',
        ),
        HolidayScheduleItem(
          id: '2025-dragon-boat',
          year: 2025,
          name: '端午节',
          nameEn: 'Dragon Boat Festival',
          startDate: DateTime(2025, 5, 31),
          endDate: DateTime(2025, 6, 2),
          totalDays: 3,
          holidayDates: [
            DateTime(2025, 5, 31),
            DateTime(2025, 6, 1),
            DateTime(2025, 6, 2),
          ],
          makeupDates: const [],
          bridgeLeaveTip: '6月3日至6日请假4天，可连休9天',
          bridgeLeaveTipEn: 'Take Jun 3–6 off (4 days) for a 9-day break.',
        ),
        HolidayScheduleItem(
          id: '2025-national-mid-autumn',
          year: 2025,
          name: '国庆中秋',
          nameEn: 'National Day & Mid-Autumn',
          startDate: DateTime(2025, 10, 1),
          endDate: DateTime(2025, 10, 8),
          totalDays: 8,
          holidayDates: _dateRange(2025, 10, 1, 8),
          makeupDates: _datesFromPairs(2025, [(9, 28), (10, 11)]),
          bridgeLeaveTip: '10月9日至11日请假3天，可连休12天',
          bridgeLeaveTipEn:
              'Take Oct 9–11 off (3 days) for a 12-day continuous break.',
        ),
      ],
      2026: <HolidayScheduleItem>[
        HolidayScheduleItem(
          id: '2026-new-year',
          year: 2026,
          name: '元旦',
          nameEn: "New Year's Day",
          startDate: DateTime(2026, 1, 1),
          endDate: DateTime(2026, 1, 3),
          totalDays: 3,
          holidayDates: _dateRange(2026, 1, 1, 3),
          makeupDates: const [],
          bridgeLeaveTip: '1月4日（周日）起请假至1月9日，可衔接前后周末',
          bridgeLeaveTipEn:
              'Extend from Jan 4 onward with annual leave for a longer trip.',
        ),
        HolidayScheduleItem(
          id: '2026-spring-festival',
          year: 2026,
          name: '春节',
          nameEn: 'Spring Festival',
          startDate: DateTime(2026, 2, 17),
          endDate: DateTime(2026, 2, 23),
          totalDays: 7,
          holidayDates: _dateRange(2026, 2, 17, 23),
          makeupDates: _datesFromPairs(2026, [(2, 15), (2, 28)]),
          bridgeLeaveTip: '2月24日至28日请假5天，可连休13天',
          bridgeLeaveTipEn: 'Take Feb 24–28 off (5 days) for a 13-day break.',
        ),
        HolidayScheduleItem(
          id: '2026-qingming',
          year: 2026,
          name: '清明节',
          nameEn: 'Qingming Festival',
          startDate: DateTime(2026, 4, 5),
          endDate: DateTime(2026, 4, 7),
          totalDays: 3,
          holidayDates: _dateRange(2026, 4, 5, 7),
          makeupDates: const [],
          bridgeLeaveTip: '4月8日至10日请假3天，可连休8天',
          bridgeLeaveTipEn: 'Take Apr 8–10 off (3 days) for an 8-day break.',
        ),
        HolidayScheduleItem(
          id: '2026-labor-day',
          year: 2026,
          name: '劳动节',
          nameEn: 'Labor Day',
          startDate: DateTime(2026, 5, 1),
          endDate: DateTime(2026, 5, 5),
          totalDays: 5,
          holidayDates: _dateRange(2026, 5, 1, 5),
          makeupDates: _datesFromPairs(2026, [(4, 26)]),
          bridgeLeaveTip: '4月27日至30日请假4天，可连休10天',
          bridgeLeaveTipEn: 'Take Apr 27–30 off (4 days) for a 10-day break.',
        ),
        HolidayScheduleItem(
          id: '2026-dragon-boat',
          year: 2026,
          name: '端午节',
          nameEn: 'Dragon Boat Festival',
          startDate: DateTime(2026, 6, 19),
          endDate: DateTime(2026, 6, 21),
          totalDays: 3,
          holidayDates: _dateRange(2026, 6, 19, 21),
          makeupDates: _datesFromPairs(2026, [(6, 28)]),
          bridgeLeaveTip: '6月15日至18日请假4天，可拼出9天长假',
          bridgeLeaveTipEn: 'Take Jun 15–18 off (4 days) for a 9-day break.',
        ),
        HolidayScheduleItem(
          id: '2026-mid-autumn',
          year: 2026,
          name: '中秋节',
          nameEn: 'Mid-Autumn Festival',
          startDate: DateTime(2026, 9, 25),
          endDate: DateTime(2026, 9, 27),
          totalDays: 3,
          holidayDates: _dateRange(2026, 9, 25, 27),
          makeupDates: _datesFromPairs(2026, [(9, 20)]),
          bridgeLeaveTip: '9月28日至30日请假3天，可与国庆连休13天',
          bridgeLeaveTipEn:
              'Take Sep 28–30 off (3 days) to connect Mid-Autumn & National Day for 13 days.',
        ),
        HolidayScheduleItem(
          id: '2026-national-day',
          year: 2026,
          name: '国庆节',
          nameEn: 'National Day',
          startDate: DateTime(2026, 10, 1),
          endDate: DateTime(2026, 10, 7),
          totalDays: 7,
          holidayDates: _dateRange(2026, 10, 1, 7),
          makeupDates: _datesFromPairs(2026, [(10, 10)]),
          bridgeLeaveTip: '9月28日至30日请假3天，可连休13天（含中秋）',
          bridgeLeaveTipEn:
              'Take Sep 28–30 off (3 days) for a 13-day break.',
        ),
      ],
      2027: <HolidayScheduleItem>[
        HolidayScheduleItem(
          id: '2027-new-year',
          year: 2027,
          name: '元旦',
          nameEn: "New Year's Day",
          startDate: DateTime(2027, 1, 1),
          endDate: DateTime(2027, 1, 3),
          totalDays: 3,
          holidayDates: _dateRange(2027, 1, 1, 3),
          makeupDates: const [],
          bridgeLeaveTip: '1月4日至8日请假5天，可与周末连休10天（无需调休）',
          bridgeLeaveTipEn:
              'Take Jan 4–8 off (5 days) for a 10-day break; no makeup workday.',
        ),
        HolidayScheduleItem(
          id: '2027-spring-festival',
          year: 2027,
          name: '春节',
          nameEn: 'Spring Festival',
          startDate: DateTime(2027, 2, 5),
          endDate: DateTime(2027, 2, 13),
          totalDays: 9,
          holidayDates: _dateRange(2027, 2, 5, 13),
          makeupDates: _datesFromPairs(2027, [(1, 31), (2, 14)]),
          bridgeLeaveTip: '2月1日至4日请假4天，可连休15天；或2月14日请假1天连休10天',
          bridgeLeaveTipEn:
              'Take Feb 1–4 off (4 days) for 15 days, or Feb 14 (1 day) for 10 days.',
        ),
        HolidayScheduleItem(
          id: '2027-qingming',
          year: 2027,
          name: '清明节',
          nameEn: 'Qingming Festival',
          startDate: DateTime(2027, 4, 3),
          endDate: DateTime(2027, 4, 5),
          totalDays: 3,
          holidayDates: _dateRange(2027, 4, 3, 5),
          makeupDates: const [],
          bridgeLeaveTip: '4月6日至9日请假4天，可连休9天',
          bridgeLeaveTipEn: 'Take Apr 6–9 off (4 days) for a 9-day break.',
        ),
        HolidayScheduleItem(
          id: '2027-labor-day',
          year: 2027,
          name: '劳动节',
          nameEn: 'Labor Day',
          startDate: DateTime(2027, 5, 1),
          endDate: DateTime(2027, 5, 5),
          totalDays: 5,
          holidayDates: _dateRange(2027, 5, 1, 5),
          makeupDates: _datesFromPairs(2027, [(5, 8)]),
          bridgeLeaveTip: '5月6日至8日请假3天，可连休9天',
          bridgeLeaveTipEn: 'Take May 6–8 off (3 days) for a 9-day break.',
        ),
        HolidayScheduleItem(
          id: '2027-dragon-boat',
          year: 2027,
          name: '端午节',
          nameEn: 'Dragon Boat Festival',
          startDate: DateTime(2027, 6, 9),
          endDate: DateTime(2027, 6, 9),
          totalDays: 1,
          holidayDates: _datesFromPairs(2027, [(6, 9)]),
          makeupDates: const [],
          bridgeLeaveTip: '6月7日至8日或10日至11日请假2天，可与周末连休5天',
          bridgeLeaveTipEn:
              'Take Jun 7–8 or Jun 10–11 off (2 days) for a 5-day break.',
        ),
        HolidayScheduleItem(
          id: '2027-mid-autumn',
          year: 2027,
          name: '中秋节',
          nameEn: 'Mid-Autumn Festival',
          startDate: DateTime(2027, 9, 15),
          endDate: DateTime(2027, 9, 15),
          totalDays: 1,
          holidayDates: _datesFromPairs(2027, [(9, 15)]),
          makeupDates: const [],
          bridgeLeaveTip: '9月13日至14日或16日至17日请假2天，可与周末连休5天',
          bridgeLeaveTipEn:
              'Take Sep 13–14 or Sep 16–17 off (2 days) for a 5-day break.',
        ),
        HolidayScheduleItem(
          id: '2027-national-day',
          year: 2027,
          name: '国庆节',
          nameEn: 'National Day',
          startDate: DateTime(2027, 10, 1),
          endDate: DateTime(2027, 10, 7),
          totalDays: 7,
          holidayDates: _dateRange(2027, 10, 1, 7),
          makeupDates: _datesFromPairs(2027, [(9, 26), (10, 9)]),
          bridgeLeaveTip: '10月8日至9日请假2天，可连休10天',
          bridgeLeaveTipEn: 'Take Oct 8–9 off (2 days) for a 10-day break.',
        ),
      ],
    };

/// 节假日服务。核心判定均为同步纯内存计算；远程刷新通过 [refreshYearFromRemote] 异步注入。
class HolidayCalendar {
  HolidayCalendar._();

  /// 工具类单例，便于上游注入 mock 时用。
  static final HolidayCalendar instance = HolidayCalendar._();

  // 可变覆盖层：`updateFrom` 的数据会进这里，优先于 `_kBuiltinHolidays`。
  static final Map<int, HolidayYear> _overrides = <int, HolidayYear>{};
  static int _cacheVersion = 0;

  static final _HolidayLruCache<(int, int, int), bool> _isHolidayCache =
      _HolidayLruCache<(int, int, int), bool>(1024);
  static final _HolidayLruCache<(int, int, int), bool> _isMakeupCache =
      _HolidayLruCache<(int, int, int), bool>(1024);
  static final _HolidayLruCache<(int, int, int, AppLocale), _HolidayCacheBox<String?>>
  _holidayNameCache =
      _HolidayLruCache<(int, int, int, AppLocale), _HolidayCacheBox<String?>>(
        512,
      );
  static final _HolidayLruCache<
    (int, int, int),
    _HolidayCacheBox<HolidayScheduleItem?>
  >
  _scheduleItemCache =
      _HolidayLruCache<
        (int, int, int),
        _HolidayCacheBox<HolidayScheduleItem?>
      >(512);
  static final _HolidayLruCache<int, List<HolidayScheduleItem>>
  _schedulesForYearCache = _HolidayLruCache<int, List<HolidayScheduleItem>>(32);
  static final _HolidayLruCache<(int, int, int, int), List<HolidayScheduleItem>>
  _upcomingHolidaysCache =
      _HolidayLruCache<(int, int, int, int), List<HolidayScheduleItem>>(128);
  static final _HolidayLruCache<
    (int, int, int),
    _HolidayCacheBox<HolidayScheduleItem?>
  >
  _nextHolidayCache =
      _HolidayLruCache<
        (int, int, int),
        _HolidayCacheBox<HolidayScheduleItem?>
      >(128);

  static int get cacheVersion => _cacheVersion;

  static void _clearCaches() {
    _cacheVersion++;
    _isHolidayCache.clear();
    _isMakeupCache.clear();
    _holidayNameCache.clear();
    _scheduleItemCache.clear();
    _schedulesForYearCache.clear();
    _upcomingHolidaysCache.clear();
    _nextHolidayCache.clear();
  }

  static const Map<String, String> _holidayEnNames = <String, String>{
    '元旦': "New Year's Day",
    '元旦节': "New Year's Day",
    '春节': 'Spring Festival',
    '清明': 'Qingming Festival',
    '清明节': 'Qingming Festival',
    '劳动节': 'Labor Day',
    '端午': 'Dragon Boat Festival',
    '端午节': 'Dragon Boat Festival',
    '中秋': 'Mid-Autumn Festival',
    '中秋节': 'Mid-Autumn Festival',
    '国庆': 'National Day',
    '国庆节': 'National Day',
    '国庆中秋': 'National Day & Mid-Autumn',
    '抗战胜利日': 'Victory Day',
    '法定假日': 'Public Holiday',
  };

  /// 已内置（或已覆盖）数据的年份列表（升序）。
  static List<int> get supportedYears {
    final years = <int>{..._kBuiltinHolidays.keys, ..._overrides.keys}.toList()
      ..sort();
    return List.unmodifiable(years);
  }

  static bool hasBuiltinOrOverrideData(int year) =>
      _overrides.containsKey(year) || _kBuiltinHolidays.containsKey(year);

  /// 当天是否是**法定放假日**。
  static bool isHoliday(DateTime day) {
    final key = (day.year, day.month, day.day);
    final cached = _isHolidayCache.get(key);
    if (cached != null) return cached;
    final year = _resolve(day.year);
    final bool result;
    if (year != null) {
      result = year.holidays.contains(_mmdd(day));
    } else {
      final fallback = _lunarHolidayFor(day);
      result = fallback != null && !fallback.isWork();
    }
    _isHolidayCache.put(key, result);
    return result;
  }

  /// 当天是否是**调休上班日**（通常是周末）。
  static bool isWorkMakeupDay(DateTime day) {
    final key = (day.year, day.month, day.day);
    final cached = _isMakeupCache.get(key);
    if (cached != null) return cached;
    final year = _resolve(day.year);
    final bool result;
    if (year != null) {
      result = year.workMakeupDays.contains(_mmdd(day));
    } else {
      final fallback = _lunarHolidayFor(day);
      result = fallback != null && fallback.isWork();
    }
    _isMakeupCache.put(key, result);
    return result;
  }

  /// 当天是否是**工作日**（非法定假日，且为调休上班日或周一至周五）。
  static bool isWorkday(DateTime day) {
    if (isHoliday(day)) return false;
    if (isWorkMakeupDay(day)) return true;
    return day.weekday >= DateTime.monday && day.weekday <= DateTime.friday;
  }

  /// 当天是否是**休息日**（法定放假或非调休周末）。
  static bool isRestDay(DateTime day) => !isWorkday(day);

  /// 若当天属于法定节假日，返回节日名称；否则返回 null。
  static String? holidayName(DateTime day, {AppLocale? locale}) {
    final effectiveLocale = locale ?? I18n.current;
    final key = (day.year, day.month, day.day, effectiveLocale);
    final cached = _holidayNameCache.get(key);
    if (cached != null) return cached.value;
    String? result;
    if (isHoliday(day)) {
      final item = scheduleItemFor(day);
      if (item != null) {
        result = item.localizedName(effectiveLocale);
      } else {
        final fallback = _lunarHolidayFor(day);
        if (fallback != null && !fallback.isWork()) {
          final raw = _normalizeHolidayName(fallback.getName());
          result = effectiveLocale == AppLocale.en
              ? (_holidayEnNames[raw] ?? raw)
              : raw;
        } else {
          result = effectiveLocale == AppLocale.en
              ? 'Public Holiday'
              : '法定假日';
        }
      }
    }
    _holidayNameCache.put(key, _HolidayCacheBox(result));
    return result;
  }

  /// 返回当天所属的节假日安排（包含放假日及对应的调休补班日）。
  static HolidayScheduleItem? scheduleItemFor(DateTime day) {
    final key = (day.year, day.month, day.day);
    final cached = _scheduleItemCache.get(key);
    if (cached != null) return cached.value;

    final target = _dateOnly(day);
    HolidayScheduleItem? found;
    final items = schedulesForYear(target.year);
    for (final item in items) {
      if (item.holidayDates.any((d) => _sameDay(d, target)) ||
          item.makeupDates.any((d) => _sameDay(d, target))) {
        found = item;
        break;
      }
    }
    // 处理跨年调休（如 12 月末的元旦补班或次年春节前补班）
    if (found == null && target.month == 12) {
      for (final item in schedulesForYear(target.year + 1)) {
        if (item.holidayDates.any((d) => _sameDay(d, target)) ||
            item.makeupDates.any((d) => _sameDay(d, target))) {
          found = item;
          break;
        }
      }
    } else if (found == null && target.month == 1) {
      for (final item in schedulesForYear(target.year - 1)) {
        if (item.holidayDates.any((d) => _sameDay(d, target)) ||
            item.makeupDates.any((d) => _sameDay(d, target))) {
          found = item;
          break;
        }
      }
    }
    _scheduleItemCache.put(key, _HolidayCacheBox(found));
    return found;
  }

  /// 获取某年的完整法定节假日安排列表（2024–2027 返回含拼假建议的结构化数据；
  /// 其余年份按 [updateFrom] 覆盖层或 `HolidayUtil` 自动聚合）。
  static List<HolidayScheduleItem> schedulesForYear(int year) {
    final cached = _schedulesForYearCache.get(year);
    if (cached != null) return cached;
    final List<HolidayScheduleItem> result;
    if (!_overrides.containsKey(year) && _kBuiltinSchedules.containsKey(year)) {
      result = List.unmodifiable(_kBuiltinSchedules[year]!);
    } else {
      final override = _overrides[year];
      if (override != null) {
        result = _buildSchedulesFromHolidayYear(year, override);
      } else {
        result = _buildSchedulesFromLunarUtil(year);
      }
    }
    _schedulesForYearCache.put(year, result);
    return result;
  }

  /// 获取从 [from] 起即将到来（或正在进行）的法定节假日安排列表。
  static List<HolidayScheduleItem> upcomingHolidays(
    DateTime from, {
    int limit = 7,
  }) {
    if (limit <= 0) return const [];
    final key = (from.year, from.month, from.day, limit);
    final cached = _upcomingHolidaysCache.get(key);
    if (cached != null) return cached;
    final base = _dateOnly(from);
    final results = <HolidayScheduleItem>[];
    final seenIds = <String>{};
    for (final y in [base.year, base.year + 1, base.year + 2]) {
      for (final item in schedulesForYear(y)) {
        final end = _dateOnly(item.endDate);
        if (!end.isBefore(base) && seenIds.add(item.id)) {
          results.add(item);
        }
      }
    }
    results.sort((a, b) => a.startDate.compareTo(b.startDate));
    final unmodifiable = results.length <= limit
        ? List<HolidayScheduleItem>.unmodifiable(results)
        : List<HolidayScheduleItem>.unmodifiable(results.take(limit));
    _upcomingHolidaysCache.put(key, unmodifiable);
    return unmodifiable;
  }

  /// 距离 [from] 最近的一个正在进行或即将到来的法定节假日。
  static HolidayScheduleItem? nextHoliday(DateTime from) {
    final key = (from.year, from.month, from.day);
    final cached = _nextHolidayCache.get(key);
    if (cached != null) return cached.value;
    final list = upcomingHolidays(from, limit: 1);
    final result = list.isEmpty ? null : list.first;
    _nextHolidayCache.put(key, _HolidayCacheBox(result));
    return result;
  }

  /// 用新数据覆盖指定年份。调用方（cloud_sync_v2 / assets loader）负责
  /// 给出正确的 `year` 与 `HolidayYear` 载荷。
  static void updateFrom(int year, HolidayYear data) {
    _overrides[year] = data;
    _clearCaches();
  }

  /// 清空覆盖层（主要用于测试）。
  static void resetOverrides() {
    _overrides.clear();
    _clearCaches();
  }

  /// 非阻塞远程刷新某年节假日数据（GET `/api/holidays/{year}`）。
  /// 未配置 [baseUrl]、离线、超时或返回格式异常时安全返回 `false`，绝不抛出异常。
  static Future<bool> refreshYearFromRemote(
    int year, {
    String? baseUrl,
    http.Client? client,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final rawBase = (baseUrl ?? '').trim();
    if (rawBase.isEmpty) return false;
    final normalized = rawBase.endsWith('/')
        ? rawBase.substring(0, rawBase.length - 1)
        : rawBase;
    final ownsClient = client == null;
    final http.Client httpClient = client ?? http.Client();
    try {
      final Uri uri = Uri.parse('$normalized/api/holidays/$year');
      if (!uri.hasScheme) return false;
      final resp = await httpClient
          .get(uri, headers: const <String, String>{'Accept': 'application/json'})
          .timeout(timeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return false;
      }
      final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
      if (decoded is! Map) return false;
      final parsed = HolidayYear.fromJson(Map<String, dynamic>.from(decoded));
      if (parsed.holidays.isEmpty && parsed.workMakeupDays.isEmpty) {
        return false;
      }
      updateFrom(year, parsed);
      return true;
    } catch (_) {
      return false;
    } finally {
      if (ownsClient) {
        httpClient.close();
      }
    }
  }

  /// 安全异步刷新当年及次年节假日配置（忽略网络异常）。
  static Future<void> refreshUpcomingFromRemote({
    DateTime? from,
    String? baseUrl,
    http.Client? client,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final anchor = from ?? DateTime.now();
    await Future.wait([
      refreshYearFromRemote(
        anchor.year,
        baseUrl: baseUrl,
        client: client,
        timeout: timeout,
      ),
      refreshYearFromRemote(
        anchor.year + 1,
        baseUrl: baseUrl,
        client: client,
        timeout: timeout,
      ),
    ]);
  }

  static HolidayYear? _resolve(int year) =>
      _overrides[year] ?? _kBuiltinHolidays[year];

  static lunar_pkg.Holiday? _lunarHolidayFor(DateTime day) {
    try {
      return lunar_pkg.HolidayUtil.getHolidayByYmd(
        day.year,
        day.month,
        day.day,
      );
    } catch (_) {
      return null;
    }
  }

  static String _normalizeHolidayName(String raw) {
    return switch (raw.trim()) {
      '元旦节' => '元旦',
      '清明节' => '清明节',
      '端午节' => '端午节',
      '中秋节' => '中秋节',
      '国庆节' => '国庆节',
      _ => raw.trim(),
    };
  }

  static List<HolidayScheduleItem> _buildSchedulesFromHolidayYear(
    int year,
    HolidayYear data,
  ) {
    final holidayDates =
        data.holidays
            .map((mmdd) => _parseMmDd(year, mmdd))
            .whereType<DateTime>()
            .toList()
          ..sort();
    if (holidayDates.isEmpty) return const [];
    final makeupDates =
        data.workMakeupDays
            .map((mmdd) => _parseMmDd(year, mmdd))
            .whereType<DateTime>()
            .toList()
          ..sort();

    final groups = <List<DateTime>>[];
    for (final d in holidayDates) {
      if (groups.isEmpty) {
        groups.add([d]);
      } else {
        final prev = groups.last.last;
        final gap = DateTime.utc(d.year, d.month, d.day)
            .difference(DateTime.utc(prev.year, prev.month, prev.day))
            .inDays;
        if (gap == 1) {
          groups.last.add(d);
        } else {
          groups.add([d]);
        }
      }
    }

    final items = <HolidayScheduleItem>[];
    for (var i = 0; i < groups.length; i++) {
      final dates = groups[i];
      final start = dates.first;
      final end = dates.last;
      final name = _inferHolidayName(start, end);
      final nameEn = _holidayEnNames[name] ?? name;
      final nearbyMakeup = makeupDates
          .where((m) {
            final diffStart = DateTime.utc(start.year, start.month, start.day)
                .difference(DateTime.utc(m.year, m.month, m.day))
                .inDays
                .abs();
            final diffEnd = DateTime.utc(end.year, end.month, end.day)
                .difference(DateTime.utc(m.year, m.month, m.day))
                .inDays
                .abs();
            return diffStart <= 10 || diffEnd <= 10;
          })
          .toList(growable: false);
      items.add(
        HolidayScheduleItem(
          id: '$year-override-$i',
          year: year,
          name: name,
          nameEn: nameEn,
          startDate: start,
          endDate: end,
          totalDays: dates.length,
          holidayDates: dates,
          makeupDates: nearbyMakeup,
        ),
      );
    }
    return List.unmodifiable(items);
  }

  static List<HolidayScheduleItem> _buildSchedulesFromLunarUtil(int year) {
    try {
      final raw = lunar_pkg.HolidayUtil.getHolidaysByYear(year);
      if (raw.isEmpty) return const [];
      final groupedHolidays = <String, List<DateTime>>{};
      final groupedMakeups = <String, List<DateTime>>{};
      final groupOrder = <String>[];
      final groupNames = <String, String>{};
      for (final h in raw) {
        final date = _parseIsoDate(h.getDay());
        if (date == null || date.year != year) continue;
        final name = _normalizeHolidayName(h.getName());
        final key = '$name@${h.getTarget()}';
        if (!groupNames.containsKey(key)) {
          groupNames[key] = name;
          groupOrder.add(key);
        }
        if (h.isWork()) {
          groupedMakeups.putIfAbsent(key, () => <DateTime>[]).add(date);
        } else {
          groupedHolidays.putIfAbsent(key, () => <DateTime>[]).add(date);
        }
      }
      final items = <HolidayScheduleItem>[];
      for (var i = 0; i < groupOrder.length; i++) {
        final key = groupOrder[i];
        final dates = (groupedHolidays[key] ?? <DateTime>[])..sort();
        if (dates.isEmpty) continue;
        final makeups = (groupedMakeups[key] ?? <DateTime>[])..sort();
        final name = groupNames[key]!;
        items.add(
          HolidayScheduleItem(
            id: '$year-lunar-$i',
            year: year,
            name: name,
            nameEn: _holidayEnNames[name] ?? name,
            startDate: dates.first,
            endDate: dates.last,
            totalDays: dates.length,
            holidayDates: dates,
            makeupDates: makeups,
          ),
        );
      }
      items.sort((a, b) => a.startDate.compareTo(b.startDate));
      return List.unmodifiable(items);
    } catch (_) {
      return const [];
    }
  }

  static String _inferHolidayName(DateTime start, DateTime end) {
    if (start.month == 1 && start.day <= 3) return '元旦';
    if (start.month == 1 || start.month == 2) return '春节';
    if (start.month == 4) return '清明节';
    if (start.month == 5 && start.day <= 7) return '劳动节';
    if (start.month == 5 || start.month == 6) return '端午节';
    if (start.month == 9) return '中秋节';
    if (start.month == 10) return '国庆节';
    return '法定假日';
  }

  static DateTime? _parseMmDd(int year, String mmdd) {
    final parts = mmdd.split('-');
    if (parts.length != 2) return null;
    final m = int.tryParse(parts[0]);
    final d = int.tryParse(parts[1]);
    if (m == null || d == null || m < 1 || m > 12 || d < 1 || d > 31) {
      return null;
    }
    final candidate = DateTime(year, m, d);
    if (candidate.month != m || candidate.day != d) return null;
    return candidate;
  }

  static DateTime? _parseIsoDate(String ymd) {
    final parts = ymd.split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _mmdd(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

final class _HolidayCacheBox<T> {
  final T value;

  const _HolidayCacheBox(this.value);
}

class _HolidayLruCache<K, V> {
  final int maxEntries;
  final LinkedHashMap<K, V> _entries = LinkedHashMap<K, V>();

  _HolidayLruCache(this.maxEntries);

  V? get(K key) {
    final value = _entries.remove(key);
    if (value != null) {
      _entries[key] = value;
    }
    return value;
  }

  void put(K key, V value) {
    if (_entries.containsKey(key)) {
      _entries.remove(key);
    } else if (_entries.length >= maxEntries) {
      _entries.remove(_entries.keys.first);
    }
    _entries[key] = value;
  }

  void clear() {
    _entries.clear();
  }
}
