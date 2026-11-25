import 'dart:collection';

import 'package:lunar/lunar.dart' as lunar_pkg;

/// 农历(阴历)日期换算工具。
/// 支持 1900-2099 年的公历↔农历转换、节气（含精确交节时刻）、干支、生肖、
/// 星座、周数、物候民俗、神煞方位、十二时辰详版与八字简排。
///
/// 核心压缩表来源：通行的中国农历压缩表(公版算法，多数开源日历库共用)。
/// 每年一个十六进制数：闰月位置 + 闰月大小 + 十二个普通月大小。
class LunarDate {
  final int year; // 农历年
  final int month; // 农历月(1-12)，若为闰月则 isLeap=true
  final int day; // 农历日(1-30)
  final bool isLeapMonth;

  const LunarDate(this.year, this.month, this.day, {this.isLeapMonth = false});

  /// "正月初一" / "三月十五"
  String get chineseText =>
      '${LunarCalendar._monthName(month, isLeapMonth)}${LunarCalendar._dayName(day)}';

  /// 仅日部分文字："初一"、"十五"
  String get dayChineseText => LunarCalendar._dayName(day);

  /// 初一时返回月名，否则返回日
  String get shortDayOrMonth => day == 1
      ? LunarCalendar._monthName(month, isLeapMonth)
      : LunarCalendar._dayName(day);

  @override
  String toString() =>
      '$year年${isLeapMonth ? '闰' : ''}${LunarCalendar._monthName(month, false)}${LunarCalendar._dayName(day)}';
}

/// 十二时辰详版吉凶与神煞信息。
class AlmanacHourFortune {
  final String ganzhi;
  final String branch;
  final String range;
  final String deity;
  final bool isAuspicious;

  // P1 十二时辰详版拓展字段（均提供安全默认值以兼容既有构造调用）
  final List<String> yi;
  final List<String> ji;
  final String caiPosition;
  final String xiPosition;
  final String fuPosition;
  final String yangGuiPosition;
  final String yinGuiPosition;
  final String chongSha;
  final String tianShenType;
  final String naYin;

  const AlmanacHourFortune({
    required this.ganzhi,
    required this.branch,
    required this.range,
    required this.deity,
    required this.isAuspicious,
    this.yi = const <String>[],
    this.ji = const <String>[],
    this.caiPosition = '',
    this.xiPosition = '',
    this.fuPosition = '',
    this.yangGuiPosition = '',
    this.yinGuiPosition = '',
    this.chongSha = '',
    this.tianShenType = '',
    this.naYin = '',
  });

  String get compactLabel => '$branch${isAuspicious ? '吉' : '凶'}';
}

/// 时辰信息语义别名，供新版黄历与工具页使用。
typedef ShichenInfo = AlmanacHourFortune;

/// 单个二十四节气的精确交节信息。
class SolarTermInfo {
  final String name;
  final DateTime exactDateTime;
  final bool isJie;

  const SolarTermInfo({
    required this.name,
    required this.exactDateTime,
    this.isJie = false,
  });

  bool get isQi => !isJie;
}

/// 下一个节气的精确倒计时数据。
class NextSolarTermInfo {
  final String name;
  final DateTime exactDateTime;
  final int daysRemaining;
  final int hoursRemaining;
  final int minutesRemaining;
  final Duration remaining;

  const NextSolarTermInfo({
    required this.name,
    required this.exactDateTime,
    required this.daysRemaining,
    required this.hoursRemaining,
    required this.minutesRemaining,
    required this.remaining,
  });
}

/// 生辰八字简排数据（基于 `lunar.getEightChar()`）。
class EightCharInfo {
  final DateTime birthDateTime;
  final LunarDate lunarDate;
  final String yearGanZhi;
  final String monthGanZhi;
  final String dayGanZhi;
  final String timeGanZhi;
  final String yearWuXing;
  final String monthWuXing;
  final String dayWuXing;
  final String timeWuXing;
  final String yearNaYin;
  final String monthNaYin;
  final String dayNaYin;
  final String timeNaYin;
  final String naYin;
  final String zodiac;
  final String dayMaster;
  final String dayMasterWuXing;
  final Map<String, int> wuXingCounts;

  EightCharInfo({
    required this.birthDateTime,
    required this.lunarDate,
    required this.yearGanZhi,
    required this.monthGanZhi,
    required this.dayGanZhi,
    required this.timeGanZhi,
    required this.yearWuXing,
    required this.monthWuXing,
    required this.dayWuXing,
    required this.timeWuXing,
    required this.yearNaYin,
    required this.monthNaYin,
    required this.dayNaYin,
    required this.timeNaYin,
    required this.naYin,
    required this.zodiac,
    required this.dayMaster,
    required this.dayMasterWuXing,
    required Map<String, int> wuXingCounts,
  }) : wuXingCounts = Map.unmodifiable(wuXingCounts);

  List<String> get fourPillars => [
    yearGanZhi,
    monthGanZhi,
    dayGanZhi,
    timeGanZhi,
  ];
}

class LunarAlmanacDetail {
  final DateTime solarDate;
  final LunarDate lunarDate;
  final String ganzhiLine;
  final String suitable;
  final String avoid;
  final String dayGanzhi;
  final String fetalGod;
  final String pengZu;
  final String fiveElements;
  final String mansion;
  final String clash;
  final String hourFortunes;
  final List<AlmanacHourFortune> hourFortuneItems;

  // P1 神煞方位
  final List<String> jiShen;
  final List<String> xiongSha;
  final String caiShenPosition;
  final String xiShenPosition;
  final String fuShenPosition;
  final String yangGuiPosition;
  final String yinGuiPosition;
  final String tianShen;
  final String tianShenType;
  final String tianShenLuck;
  final String zhiXing;
  final String dayNaYin;
  final String dayChongShengXiao;
  final String yearZodiac;

  // P1 物候民俗 & 星座 & 周数 & 精确节气
  final String? shuJiu;
  final String? sanFu;
  final String wuHou;
  final String hou;
  final String yueXiang;
  final String xingZuo;
  final int isoWeekNumber;
  final int dayOfYear;
  final String? currentSolarTerm;
  final DateTime? currentSolarTermExactTime;
  final NextSolarTermInfo? nextSolarTerm;

  LunarAlmanacDetail({
    required this.solarDate,
    required this.lunarDate,
    required this.ganzhiLine,
    required this.suitable,
    required this.avoid,
    required this.dayGanzhi,
    required this.fetalGod,
    required this.pengZu,
    required this.fiveElements,
    required this.mansion,
    required this.clash,
    required this.hourFortunes,
    required List<AlmanacHourFortune> hourFortuneItems,
    List<String> jiShen = const <String>[],
    List<String> xiongSha = const <String>[],
    this.caiShenPosition = '',
    this.xiShenPosition = '',
    this.fuShenPosition = '',
    this.yangGuiPosition = '',
    this.yinGuiPosition = '',
    this.tianShen = '',
    this.tianShenType = '',
    this.tianShenLuck = '',
    this.zhiXing = '',
    this.dayNaYin = '',
    this.dayChongShengXiao = '',
    this.yearZodiac = '',
    this.shuJiu,
    this.sanFu,
    this.wuHou = '',
    this.hou = '',
    this.yueXiang = '',
    this.xingZuo = '',
    this.isoWeekNumber = 1,
    this.dayOfYear = 1,
    this.currentSolarTerm,
    this.currentSolarTermExactTime,
    this.nextSolarTerm,
  }) : hourFortuneItems = List.unmodifiable(hourFortuneItems),
       jiShen = List.unmodifiable(jiShen),
       xiongSha = List.unmodifiable(xiongSha);

  bool get isHuangDao => tianShenType == '黄道';
}

class LunarCalendar {
  // 1900-01-31 是农历 1900 年正月初一
  static const int _baseYear = 1900;
  static final DateTime _baseDate = DateTime(1900, 1, 31);

  // 200 年的农历数据表：每年 20 位
  // bit19..8  闰月分布(12 位)，第 i 位=1 表 i 月大(30 日)
  // bit7..4   闰月月份(0=无闰)
  // bit3      闰月大小
  // 常见压缩表(1900-2100)
  static const List<int> _lunarInfo = [
    0x04bd8, 0x04ae0, 0x0a570, 0x054d5, 0x0d260, 0x0d950, 0x16554, 0x056a0,
    0x09ad0, 0x055d2, // 1900-1909
    0x04ae0, 0x0a5b6, 0x0a4d0, 0x0d250, 0x1d255, 0x0b540, 0x0d6a0, 0x0ada2,
    0x095b0, 0x14977, // 1910-1919
    0x04970, 0x0a4b0, 0x0b4b5, 0x06a50, 0x06d40, 0x1ab54, 0x02b60, 0x09570,
    0x052f2, 0x04970, // 1920-1929
    0x06566, 0x0d4a0, 0x0ea50, 0x06e95, 0x05ad0, 0x02b60, 0x186e3, 0x092e0,
    0x1c8d7, 0x0c950, // 1930-1939
    0x0d4a0, 0x1d8a6, 0x0b550, 0x056a0, 0x1a5b4, 0x025d0, 0x092d0, 0x0d2b2,
    0x0a950, 0x0b557, // 1940-1949
    0x06ca0, 0x0b550, 0x15355, 0x04da0, 0x0a5b0, 0x14573, 0x052b0, 0x0a9a8,
    0x0e950, 0x06aa0, // 1950-1959
    0x0aea6, 0x0ab50, 0x04b60, 0x0aae4, 0x0a570, 0x05260, 0x0f263, 0x0d950,
    0x05b57, 0x056a0, // 1960-1969
    0x096d0, 0x04dd5, 0x04ad0, 0x0a4d0, 0x0d4d4, 0x0d250, 0x0d558, 0x0b540,
    0x0b6a0, 0x195a6, // 1970-1979
    0x095b0, 0x049b0, 0x0a974, 0x0a4b0, 0x0b27a, 0x06a50, 0x06d40, 0x0af46,
    0x0ab60, 0x09570, // 1980-1989
    0x04af5, 0x04970, 0x064b0, 0x074a3, 0x0ea50, 0x06b58, 0x055c0, 0x0ab60,
    0x096d5, 0x092e0, // 1990-1999
    0x0c960, 0x0d954, 0x0d4a0, 0x0da50, 0x07552, 0x056a0, 0x0abb7, 0x025d0,
    0x092d0, 0x0cab5, // 2000-2009
    0x0a950, 0x0b4a0, 0x0baa4, 0x0ad50, 0x055d9, 0x04ba0, 0x0a5b0, 0x15176,
    0x052b0, 0x0a930, // 2010-2019
    0x07954, 0x06aa0, 0x0ad50, 0x05b52, 0x04b60, 0x0a6e6, 0x0a4e0, 0x0d260,
    0x0ea65, 0x0d530, // 2020-2029
    0x05aa0, 0x076a3, 0x096d0, 0x04afb, 0x04ad0, 0x0a4d0, 0x1d0b6, 0x0d250,
    0x0d520, 0x0dd45, // 2030-2039
    0x0b5a0, 0x056d0, 0x055b2, 0x049b0, 0x0a577, 0x0a4b0, 0x0aa50, 0x1b255,
    0x06d20, 0x0ada0, // 2040-2049
    0x14b63, 0x09370, 0x049f8, 0x04970, 0x064b0, 0x168a6, 0x0ea50, 0x06b20,
    0x1a6c4, 0x0aae0, // 2050-2059
    0x0a2e0, 0x0d2e3, 0x0c960, 0x0d557, 0x0d4a0, 0x0da50, 0x05d55, 0x056a0,
    0x0a6d0, 0x055d4, // 2060-2069
    0x052d0, 0x0a9b8, 0x0a950, 0x0b4a0, 0x0b6a6, 0x0ad50, 0x055a0, 0x0aba4,
    0x0a5b0, 0x052b0, // 2070-2079
    0x0b273, 0x06930, 0x07337, 0x06aa0, 0x0ad50, 0x14b55, 0x04b60, 0x0a570,
    0x054e4, 0x0d160, // 2080-2089
    0x0e968, 0x0d520, 0x0daa0, 0x16aa6, 0x056d0, 0x04ae0, 0x0a9d4, 0x0a2d0,
    0x0d150, 0x0f252, // 2090-2099
    0x0d520, // 2100
  ];

  static const List<String> _heavenlyStems = [
    '甲',
    '乙',
    '丙',
    '丁',
    '戊',
    '己',
    '庚',
    '辛',
    '壬',
    '癸',
  ];
  static const List<String> _earthlyBranches = [
    '子',
    '丑',
    '寅',
    '卯',
    '辰',
    '巳',
    '午',
    '未',
    '申',
    '酉',
    '戌',
    '亥',
  ];
  static const List<String> _branchZodiac = [
    '鼠',
    '牛',
    '虎',
    '兔',
    '龙',
    '蛇',
    '马',
    '羊',
    '猴',
    '鸡',
    '狗',
    '猪',
  ];

  /// 返回某农历年总天数
  static int _yearDays(int year) {
    int sum = 348;
    for (int i = 0x8000; i > 0x8; i >>= 1) {
      sum += (_lunarInfo[year - _baseYear] & i) != 0 ? 1 : 0;
    }
    return sum + _leapDays(year);
  }

  /// 返回某农历年闰月月份(0 表示无闰月)
  static int _leapMonth(int year) => _lunarInfo[year - _baseYear] & 0xf;

  /// 返回某农历年闰月天数
  static int _leapDays(int year) {
    if (_leapMonth(year) == 0) return 0;
    return (_lunarInfo[year - _baseYear] & 0x10000) != 0 ? 30 : 29;
  }

  /// 返回农历 y 年 m 月的天数(m 为非闰月)
  static int _monthDays(int year, int month) {
    return (_lunarInfo[year - _baseYear] & (0x10000 >> month)) != 0 ? 30 : 29;
  }

  /// 返回某农历年的闰月月份（0 表示当年无闰月，1–12 表示闰几月）。
  static int leapMonthOfLunarYear(int lunarYear) {
    try {
      return lunar_pkg.LunarYear.fromYear(lunarYear).getLeapMonth();
    } catch (_) {
      if (lunarYear < _baseYear || lunarYear >= _baseYear + _lunarInfo.length) {
        return 0;
      }
      return _leapMonth(lunarYear);
    }
  }

  /// 返回某农历年月的天数，完整支持闰月（[isLeap] = true）。
  static int daysInLunarMonth(int year, int month, {bool isLeap = false}) {
    if (month < 1 || month > 12) return 29;
    try {
      final monthCode = isLeap ? -month : month;
      final count = lunar_pkg.LunarMonth.fromYm(year, monthCode)?.getDayCount();
      if (count != null && count > 0) return count;
      if (isLeap) return 0;
    } catch (_) {
      // Fall back to the bundled table below.
    }
    if (year < _baseYear || year >= _baseYear + _lunarInfo.length) return 29;
    if (isLeap) {
      return _leapMonth(year) == month ? _leapDays(year) : 0;
    }
    return _monthDays(year, month);
  }

  static int daysInMonth(int year, int month, {bool isLeap = false}) {
    if (year < _baseYear || year >= _baseYear + _lunarInfo.length) return 29;
    if (month < 1 || month > 12) return 29;
    final fromLib = daysInLunarMonth(year, month, isLeap: isLeap);
    if (fromLib > 0) return fromLib;
    if (isLeap && _leapMonth(year) == month) return _leapDays(year);
    return _monthDays(year, month);
  }

  static String monthName(int month, {bool isLeap = false}) =>
      _monthName(month, isLeap);

  static String dayName(int day) => _dayName(day);

  /// The app's documented display range, independent of the library's wider
  /// calculation range. A Solar date in January 1900 may belong to lunar 1899.
  static bool isWithinDocumentedSolarRange(DateTime date) =>
      date.year >= 1900 && date.year <= 2099;

  /// Returns the library's conversion, or null when that civil day cannot be
  /// represented or converted. Does not use [fromSolar]'s clamped fallback.
  /// Outside [isWithinDocumentedSolarRange], the library's historical calendar
  /// rules are not a guarantee of proleptic Gregorian astronomical accuracy.
  static LunarDate? tryFromSolar(DateTime date) {
    try {
      final solarDate = _dateOnly(date);
      if (!_sameSolarDay(solarDate, date)) {
        return null;
      }
      return _lunarDateFromLunar(_lunarFor(solarDate));
    } catch (_) {
      return null;
    }
  }

  /// 公历 → 农历
  static LunarDate fromSolar(DateTime date) {
    try {
      final lunar = _lunarFor(date);
      return _lunarDateFromLunar(lunar);
    } catch (_) {
      // Keep the bundled table as a fallback for out-of-range or library edge cases.
    }
    final solarDate = DateTime(date.year, date.month, date.day);
    if (solarDate.isBefore(_baseDate)) {
      return const LunarDate(_baseYear, 1, 1);
    }

    int offset = solarDate.difference(_baseDate).inDays;
    int year = _baseYear;
    final lastYear = _baseYear + _lunarInfo.length - 1;
    int yearDays = _yearDays(year);
    while (offset >= yearDays) {
      if (year >= lastYear) {
        return _lastSupportedLunarDate();
      }
      offset -= yearDays;
      year++;
      yearDays = _yearDays(year);
    }

    final leap = _leapMonth(year);
    bool isLeap = false;
    int month = 1;
    int daysInMonth;

    for (month = 1; month <= 12; month++) {
      if (leap > 0 && month == leap + 1 && !isLeap) {
        // 进入闰月
        --month;
        isLeap = true;
        daysInMonth = _leapDays(year);
      } else {
        daysInMonth = _monthDays(year, month);
      }
      if (isLeap && month == leap + 1) isLeap = false;
      if (offset < daysInMonth) break;
      offset -= daysInMonth;
    }
    // month 越界兜底
    if (month > 12) month = 12;
    final day = offset + 1;
    return LunarDate(year, month, day, isLeapMonth: isLeap);
  }

  static LunarDate _lastSupportedLunarDate() {
    final year = _baseYear + _lunarInfo.length - 1;
    if (_leapMonth(year) == 12) {
      return LunarDate(year, 12, _leapDays(year), isLeapMonth: true);
    }
    return LunarDate(year, 12, _monthDays(year, 12));
  }

  /// 农历 → 公历（[toSolar] 语义别名，完整支持闰月）。
  static DateTime lunarToSolar(
    int lunarYear,
    int lunarMonth,
    int lunarDay, {
    bool isLeap = false,
  }) => toSolar(lunarYear, lunarMonth, lunarDay, isLeap: isLeap);

  /// 严格的农历 → 公历转换；当指定年不存在该闰月或日期非法时返回 `null`。
  static DateTime? tryToSolar(
    int lunarYear,
    int lunarMonth,
    int lunarDay, {
    bool isLeap = false,
  }) {
    if (lunarMonth < 1 || lunarMonth > 12 || lunarDay < 1 || lunarDay > 30) {
      return null;
    }
    if (isLeap && leapMonthOfLunarYear(lunarYear) != lunarMonth) {
      return null;
    }
    try {
      final lunar = lunar_pkg.Lunar.fromYmd(
        lunarYear,
        isLeap ? -lunarMonth : lunarMonth,
        lunarDay,
      );
      final solar = lunar.getSolar();
      return DateTime(solar.getYear(), solar.getMonth(), solar.getDay());
    } catch (_) {
      return null;
    }
  }

  /// 农历 → 公历
  /// 忽略闰月时，如果该年没有该月，当成普通月处理。
  static DateTime toSolar(
    int lunarYear,
    int lunarMonth,
    int lunarDay, {
    bool isLeap = false,
  }) {
    try {
      final lunar = lunar_pkg.Lunar.fromYmd(
        lunarYear,
        isLeap ? -lunarMonth : lunarMonth,
        lunarDay,
      );
      final solar = lunar.getSolar();
      return DateTime(solar.getYear(), solar.getMonth(), solar.getDay());
    } catch (_) {
      // Fall back to the bundled table below.
    }
    int offset = 0;
    for (int y = _baseYear; y < lunarYear; y++) {
      offset += _yearDays(y);
    }

    final leap = _leapMonth(lunarYear);
    for (int m = 1; m < lunarMonth; m++) {
      offset += _monthDays(lunarYear, m);
      if (leap == m) offset += _leapDays(lunarYear);
    }
    if (isLeap && leap == lunarMonth) {
      offset += _monthDays(lunarYear, lunarMonth);
    }
    offset += lunarDay - 1;
    return _baseDate.add(Duration(days: offset));
  }

  /// 生肖: 0=鼠 1=牛...11=猪
  static String zodiacOf(int lunarYear) {
    return _branchZodiac[_positiveMod(lunarYear - 4, 12)];
  }

  /// 干支纪年，如 "甲子"
  static String ganzhiOf(int lunarYear) {
    final g = _positiveMod(lunarYear - 4, 10);
    final z = _positiveMod(lunarYear - 4, 12);
    return '${_heavenlyStems[g]}${_earthlyBranches[z]}';
  }

  /// 干支纪日，如 "戊辰"。
  static String ganzhiDay(DateTime date) {
    return _lunarFor(date).getDayInGanZhi();
  }

  /// ISO-8601 周数（1–53）。
  static int isoWeekNumber(DateTime date) {
    final d = DateTime.utc(date.year, date.month, date.day);
    final thursday = d.add(Duration(days: DateTime.thursday - d.weekday));
    final jan1 = DateTime.utc(thursday.year, 1, 1);
    return (thursday.difference(jan1).inDays ~/ 7) + 1;
  }

  /// 当年第几天（1–366）。
  static int dayOfYear(DateTime date) {
    final d = DateTime.utc(date.year, date.month, date.day);
    final jan1 = DateTime.utc(date.year, 1, 1);
    return d.difference(jan1).inDays + 1;
  }

  /// 星座名（如 "双子"，不含"座"字，便于多语言格式化）。
  static String xingZuo(DateTime date) {
    return lunar_pkg.Solar.fromYmd(date.year, date.month, date.day).getXingZuo();
  }

  /// 当日若为节气日，返回精确交节时刻；否则返回 `null`。
  static DateTime? solarTermExactTime(DateTime date) {
    try {
      final jq = _lunarFor(date).getCurrentJieQi();
      if (jq == null) return null;
      final s = jq.getSolar();
      return DateTime(
        s.getYear(),
        s.getMonth(),
        s.getDay(),
        s.getHour(),
        s.getMinute(),
        s.getSecond(),
      );
    } catch (_) {
      return null;
    }
  }

  /// 从 [from] 时刻起算的下一个节气及其精确倒计时。
  static NextSolarTermInfo? nextSolarTerm(DateTime from) {
    try {
      final solar = lunar_pkg.Solar.fromYmdHms(
        from.year,
        from.month,
        from.day,
        from.hour,
        from.minute,
        from.second,
      );
      final jq = solar.getLunar().getNextJieQi(false);
      final s = jq.getSolar();
      final exact = DateTime(
        s.getYear(),
        s.getMonth(),
        s.getDay(),
        s.getHour(),
        s.getMinute(),
        s.getSecond(),
      );
      final remaining = DateTime.utc(
        s.getYear(),
        s.getMonth(),
        s.getDay(),
        s.getHour(),
        s.getMinute(),
        s.getSecond(),
      ).difference(
        DateTime.utc(
          from.year,
          from.month,
          from.day,
          from.hour,
          from.minute,
          from.second,
        ),
      );
      final safeRemaining = remaining.isNegative ? Duration.zero : remaining;
      return NextSolarTermInfo(
        name: jq.getName(),
        exactDateTime: exact,
        daysRemaining: safeRemaining.inDays,
        hoursRemaining: safeRemaining.inHours % 24,
        minutesRemaining: safeRemaining.inMinutes % 60,
        remaining: safeRemaining,
      );
    } catch (_) {
      return null;
    }
  }

  /// 返回公历 [year] 年全年的 24 节气及其精确交节时刻（按时间升序排列）。
  static List<SolarTermInfo> yearSolarTerms(int year) {
    try {
      final ly = lunar_pkg.LunarYear.fromYear(year);
      final jds = ly.getJieQiJulianDays();
      final byName = <String, SolarTermInfo>{};
      final names = lunar_pkg.Lunar.JIE_QI_IN_USE;
      for (var i = 0; i < names.length && i < jds.length; i++) {
        final s = lunar_pkg.Solar.fromJulianDay(jds[i]);
        if (s.getYear() != year) continue;
        final canonical = _normalizeJieQiName(names[i]);
        final jqIdx = lunar_pkg.JieQi.JIE_QI.indexOf(canonical);
        byName[canonical] = SolarTermInfo(
          name: canonical,
          exactDateTime: DateTime(
            s.getYear(),
            s.getMonth(),
            s.getDay(),
            s.getHour(),
            s.getMinute(),
            s.getSecond(),
          ),
          isJie: jqIdx >= 0 ? jqIdx.isOdd : false,
        );
      }
      final list = byName.values.toList()
        ..sort((a, b) => a.exactDateTime.compareTo(b.exactDateTime));
      return List.unmodifiable(list);
    } catch (_) {
      return const [];
    }
  }

  /// 生辰八字简排（四柱、五行、纳音、生肖）。
  static EightCharInfo eightChar(DateTime birthDateTime) {
    final solar = lunar_pkg.Solar.fromYmdHms(
      birthDateTime.year,
      birthDateTime.month,
      birthDateTime.day,
      birthDateTime.hour,
      birthDateTime.minute,
      birthDateTime.second,
    );
    final lunar = solar.getLunar();
    final ec = lunar.getEightChar();
    final yearWx = ec.getYearWuXing();
    final monthWx = ec.getMonthWuXing();
    final dayWx = ec.getDayWuXing();
    final timeWx = ec.getTimeWuXing();
    final counts = <String, int>{'金': 0, '木': 0, '水': 0, '火': 0, '土': 0};
    for (final segment in [yearWx, monthWx, dayWx, timeWx]) {
      for (final rune in segment.runes) {
        final ch = String.fromCharCode(rune);
        if (counts.containsKey(ch)) {
          counts[ch] = counts[ch]! + 1;
        }
      }
    }
    final yearNaYin = ec.getYearNaYin();
    final monthNaYin = ec.getMonthNaYin();
    final dayNaYin = ec.getDayNaYin();
    final timeNaYin = ec.getTimeNaYin();
    final dayMaster = ec.getDayGan();
    final dayMasterWx = dayWx.isNotEmpty ? dayWx.substring(0, 1) : '';
    return EightCharInfo(
      birthDateTime: birthDateTime,
      lunarDate: _lunarDateFromLunar(lunar),
      yearGanZhi: ec.getYear(),
      monthGanZhi: ec.getMonth(),
      dayGanZhi: ec.getDay(),
      timeGanZhi: ec.getTime(),
      yearWuXing: yearWx,
      monthWuXing: monthWx,
      dayWuXing: dayWx,
      timeWuXing: timeWx,
      yearNaYin: yearNaYin,
      monthNaYin: monthNaYin,
      dayNaYin: dayNaYin,
      timeNaYin: timeNaYin,
      naYin: '$yearNaYin · $monthNaYin · $dayNaYin · $timeNaYin',
      zodiac: lunar.getYearShengXiaoExact(),
      dayMaster: dayMaster,
      dayMasterWuXing: dayMasterWx,
      wuXingCounts: counts,
    );
  }

  static EightCharInfo? tryEightChar(DateTime birthDateTime) {
    try {
      final solarDate = _dateOnly(birthDateTime);
      if (!_sameSolarDay(solarDate, birthDateTime)) {
        return null;
      }
      return eightChar(birthDateTime);
    } catch (_) {
      return null;
    }
  }

  static final _LunarLruCache<(int, int, int), LunarAlmanacDetail>
  _almanacDetailCache = _LunarLruCache<(int, int, int), LunarAlmanacDetail>(
    128,
  );
  static final _LunarLruCache<(int, int, int), _LunarCacheBox<LunarAlmanacDetail?>>
  _tryAlmanacDetailCache =
      _LunarLruCache<(int, int, int), _LunarCacheBox<LunarAlmanacDetail?>>(128);
  static final _LunarLruCache<(int, int, int), _LunarCacheBox<String?>>
  _solarTermCache = _LunarLruCache<(int, int, int), _LunarCacheBox<String?>>(
    512,
  );
  static final _LunarLruCache<(int, int, int), _LunarCacheBox<String?>>
  _solarFestivalCache =
      _LunarLruCache<(int, int, int), _LunarCacheBox<String?>>(512);
  static final _LunarLruCache<(int, int, int), _LunarCacheBox<String?>>
  _lunarFestivalCache =
      _LunarLruCache<(int, int, int), _LunarCacheBox<String?>>(512);

  static LunarAlmanacDetail almanacDetail(DateTime date) {
    final solarDate = _dateOnly(date);
    final cacheKey = (solarDate.year, solarDate.month, solarDate.day);
    final cached = _almanacDetailCache.get(cacheKey);
    if (cached != null) return cached;
    final solar = lunar_pkg.Solar.fromYmd(
      solarDate.year,
      solarDate.month,
      solarDate.day,
    );
    final lunar = solar.getLunar();
    final hours = _hourFortunesForLunar(lunar);
    final currentJq = lunar.getCurrentJieQi();
    final currentJqName = currentJq?.getName();
    final currentJqTime = currentJq == null
        ? null
        : DateTime(
            currentJq.getSolar().getYear(),
            currentJq.getSolar().getMonth(),
            currentJq.getSolar().getDay(),
            currentJq.getSolar().getHour(),
            currentJq.getSolar().getMinute(),
            currentJq.getSolar().getSecond(),
          );
    final detail = LunarAlmanacDetail(
      solarDate: solarDate,
      lunarDate: _lunarDateFromLunar(lunar),
      ganzhiLine: _ganzhiLineForLunar(lunar),
      suitable: _suitableForLunar(lunar),
      avoid: _avoidForLunar(lunar),
      dayGanzhi: lunar.getDayInGanZhi(),
      fetalGod: _compactText(lunar.getDayPositionTai()),
      pengZu: _pengZuText(lunar),
      fiveElements: '${lunar.getDayNaYin()}${lunar.getZhiXing()}执位',
      mansion:
          '${_mansionDirection(lunar.getGong())}${lunar.getXiu()}${lunar.getZheng()}${lunar.getAnimal()}-${lunar.getXiuLuck()}',
      clash: _clashText(lunar),
      hourFortunes: _hourFortuneSummary(hours),
      hourFortuneItems: hours,
      jiShen: _dayShenShaForLunar(lunar, auspicious: true),
      xiongSha: _dayShenShaForLunar(lunar, auspicious: false),
      caiShenPosition: lunar.getDayPositionCaiDesc(),
      xiShenPosition: lunar.getDayPositionXiDesc(),
      fuShenPosition: lunar.getDayPositionFuDesc(),
      yangGuiPosition: lunar.getDayPositionYangGuiDesc(),
      yinGuiPosition: lunar.getDayPositionYinGuiDesc(),
      tianShen: lunar.getDayTianShen(),
      tianShenType: lunar.getDayTianShenType(),
      tianShenLuck: lunar.getDayTianShenLuck(),
      zhiXing: lunar.getZhiXing(),
      dayNaYin: lunar.getDayNaYin(),
      dayChongShengXiao: lunar.getDayChongShengXiao(),
      yearZodiac: lunar.getYearShengXiao(),
      shuJiu: lunar.getShuJiu()?.toFullString(),
      sanFu: lunar.getFu()?.toFullString(),
      wuHou: lunar.getWuHou(),
      hou: lunar.getHou(),
      yueXiang: lunar.getYueXiang(),
      xingZuo: solar.getXingZuo(),
      isoWeekNumber: isoWeekNumber(solarDate),
      dayOfYear: dayOfYear(solarDate),
      currentSolarTerm: (currentJqName == null || currentJqName.isEmpty)
          ? null
          : currentJqName,
      currentSolarTermExactTime: currentJqTime,
      nextSolarTerm: nextSolarTerm(solarDate),
    );
    _almanacDetailCache.put(cacheKey, detail);
    return detail;
  }

  /// Queries almanac data without changing the requested civil day or exposing
  /// conversion errors to the UI. The documented display policy is separate.
  static LunarAlmanacDetail? tryAlmanacDetail(DateTime date) {
    final solarDate = _dateOnly(date);
    if (!_sameSolarDay(solarDate, date)) {
      return null;
    }
    final cacheKey = (solarDate.year, solarDate.month, solarDate.day);
    final cached = _tryAlmanacDetailCache.get(cacheKey);
    if (cached != null) return cached.value;
    try {
      final detail = almanacDetail(solarDate);
      final result = _sameSolarDay(detail.solarDate, date) ? detail : null;
      _tryAlmanacDetailCache.put(cacheKey, _LunarCacheBox(result));
      return result;
    } catch (_) {
      _tryAlmanacDetailCache.put(
        cacheKey,
        const _LunarCacheBox<LunarAlmanacDetail?>(null),
      );
      return null;
    }
  }

  static String almanacGanzhiLine(DateTime date, LunarDate lunar) {
    final day = _lunarFor(date);
    return _ganzhiLineForLunar(day);
  }

  static String fetalGod(DateTime date) =>
      _compactText(_lunarFor(date).getDayPositionTai());

  static String pengZu(DateTime date) => _pengZuText(_lunarFor(date));

  static String fiveElements(DateTime date) =>
      '${_lunarFor(date).getDayNaYin()}${_lunarFor(date).getZhiXing()}执位';

  static String twentyEightMansion(DateTime date) {
    final lunar = _lunarFor(date);
    return '${_mansionDirection(lunar.getGong())}${lunar.getXiu()}${lunar.getZheng()}${lunar.getAnimal()}-${lunar.getXiuLuck()}';
  }

  static String clashAndDirection(DateTime date) {
    return _clashText(_lunarFor(date));
  }

  static List<AlmanacHourFortune> hourFortunes(DateTime date) {
    return _hourFortunesForLunar(_lunarFor(date));
  }

  static String hourFortuneSummary(DateTime date) =>
      _hourFortuneSummary(hourFortunes(date));

  static List<AlmanacHourFortune> _hourFortunesForLunar(lunar_pkg.Lunar lunar) {
    const hourRanges = [
      '23:00-00:59',
      '01:00-02:59',
      '03:00-04:59',
      '05:00-06:59',
      '07:00-08:59',
      '09:00-10:59',
      '11:00-12:59',
      '13:00-14:59',
      '15:00-16:59',
      '17:00-18:59',
      '19:00-20:59',
      '21:00-22:59',
    ];
    final times = lunar.getTimes();
    return List.generate(hourRanges.length, (index) {
      final time = times[index];
      final luck = time.getTianShenLuck();
      return AlmanacHourFortune(
        ganzhi: time.getGanZhi(),
        branch: time.getZhi(),
        range: hourRanges[index],
        deity: time.getTianShen(),
        isAuspicious: luck == '吉',
        yi: _cleanTermList(time.getYi()),
        ji: _cleanTermList(time.getJi()),
        caiPosition: time.getPositionCaiDesc(),
        xiPosition: time.getPositionXiDesc(),
        fuPosition: time.getPositionFuDesc(),
        yangGuiPosition: time.getPositionYangGuiDesc(),
        yinGuiPosition: time.getPositionYinGuiDesc(),
        chongSha:
            '冲${time.getChongShengXiao()}（${time.getChongGan()}${time.getChong()}）煞${time.getSha()}',
        tianShenType: time.getTianShenType(),
        naYin: time.getNaYin(),
      );
    });
  }

  static List<String> _dayShenShaForLunar(
    lunar_pkg.Lunar lunar, {
    required bool auspicious,
  }) {
    final fromLib = _cleanShenShaList(
      auspicious ? lunar.getDayJiShen() : lunar.getDayXiongSha(),
    );
    if (fromLib.isNotEmpty) return fromLib;

    // lunar 1.7.8's LunarUtil.getDayJiShen/getDayXiongSha match DAY_SHEN_SHA
    // with lowercase hex (`toRadixString(16)`), missing the 24/60 days whose
    // JiaZi index contains A-F (e.g. 戊申 = 0x2C). Query the same table using
    // uppercase hex via LunarUtil.hex().
    var monthTableIndex =
        lunar.getMonthZhiIndex() - lunar_pkg.LunarUtil.BASE_MONTH_ZHI_INDEX;
    if (monthTableIndex < 0) monthTableIndex += 12;
    if (monthTableIndex < 0 ||
        monthTableIndex >= lunar_pkg.LunarUtil.DAY_SHEN_SHA.length) {
      return const <String>[];
    }
    final jiaZiIndex = lunar_pkg.LunarUtil.getJiaZiIndex(
      lunar.getDayInGanZhi(),
    );
    if (jiaZiIndex < 0) return const <String>[];
    final key = lunar_pkg.LunarUtil.hex(jiaZiIndex);
    final match = RegExp(
      ';$key([^;]*)',
    ).firstMatch(lunar_pkg.LunarUtil.DAY_SHEN_SHA[monthTableIndex]);
    if (match == null) return const <String>[];
    final data = match.group(1) ?? '';
    final result = <String>[];
    for (var i = 0; i + 1 < data.length; i += 2) {
      final index = int.tryParse(data.substring(i, i + 2), radix: 16);
      if (index == null ||
          index < 0 ||
          index >= lunar_pkg.LunarUtil.SHEN_SHA.length) {
        continue;
      }
      if (auspicious ? index < 60 : index >= 60) {
        final name = lunar_pkg.LunarUtil.SHEN_SHA[index].trim();
        if (name.isNotEmpty && name != '无') {
          result.add(name);
        }
      }
    }
    return List.unmodifiable(result);
  }

  static List<String> _cleanShenShaList(List<String> raw) {
    return raw
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty && s != '无')
        .toList(growable: false);
  }

  static List<String> _cleanTermList(List<String> raw) {
    return raw
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
  }

  static String _hourFortuneSummary(List<AlmanacHourFortune> hours) =>
      hours.map((item) => item.compactLabel).join(' ');

  static lunar_pkg.Lunar _lunarFor(DateTime date) =>
      lunar_pkg.Lunar.fromDate(_dateOnly(date));

  static DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  static bool _sameSolarDay(DateTime first, DateTime second) =>
      first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;

  static LunarDate _lunarDateFromLunar(lunar_pkg.Lunar lunar) {
    final month = lunar.getMonth();
    return LunarDate(
      lunar.getYear(),
      month.abs(),
      lunar.getDay(),
      isLeapMonth: month < 0,
    );
  }

  static String _compactText(String value) => value.replaceAll(' ', '');

  static String _ganzhiLineForLunar(lunar_pkg.Lunar lunar) =>
      '${lunar.getYearInGanZhi()}${lunar.getYearShengXiao()}年${lunar.getMonthInGanZhi()}月${lunar.getDayInGanZhi()}日';

  static String _pengZuText(lunar_pkg.Lunar lunar) =>
      '${_punctuatePengZu(lunar.getPengZuGan())}；${_punctuatePengZu(lunar.getPengZuZhi())}';

  static String _punctuatePengZu(String value) {
    final text = _compactText(value);
    if (text.contains('，') || text.length <= 4) return text;
    return '${text.substring(0, 4)}，${text.substring(4)}';
  }

  static String _clashText(lunar_pkg.Lunar lunar) =>
      '${lunar.getDayShengXiao()}日冲${lunar.getDayChongShengXiao()}（${lunar.getDayChongGan()}${lunar.getDayChong()}）煞${lunar.getDaySha()}';

  static String _mansionDirection(String gong) {
    switch (gong) {
      case '东':
        return '东方';
      case '西':
        return '西方';
      case '南':
        return '南方';
      case '北':
        return '北方';
      default:
        return gong;
    }
  }

  static String _normalizeJieQiName(String raw) {
    return switch (raw) {
      'DONG_ZHI' => '冬至',
      'DA_HAN' => '大寒',
      'XIAO_HAN' => '小寒',
      'LI_CHUN' => '立春',
      'YU_SHUI' => '雨水',
      'JING_ZHE' => '惊蛰',
      'DA_XUE' => '大雪',
      _ => raw,
    };
  }

  static int _positiveMod(int value, int mod) {
    final result = value % mod;
    return result < 0 ? result + mod : result;
  }

  /// 是否节气日，返回该日节气名，无则返回 null。
  /// 使用 lunar 库的节气表，和黄历详情保持同源。
  static String? solarTerm(DateTime date) {
    final cacheKey = (date.year, date.month, date.day);
    final cached = _solarTermCache.get(cacheKey);
    if (cached != null) return cached.value;
    final value = _lunarFor(date).getJieQi();
    final result = value.isEmpty ? null : value;
    _solarTermCache.put(cacheKey, _LunarCacheBox(result));
    return result;
  }

  static const Map<String, String> _solarFestivalOverrides = <String, String>{
    '1-1': '元旦',
    '2-14': '情人节',
    '3-8': '妇女节',
    '3-12': '植树节',
    '4-1': '愚人节',
    '5-1': '劳动节',
    '5-4': '青年节',
    '6-1': '儿童节',
    '7-1': '建党节',
    '8-1': '建军节',
    '9-10': '教师节',
    '10-1': '国庆节',
    '12-24': '平安夜',
    '12-25': '圣诞节',
  };

  /// 公历节日（先匹配内置核心节日保持简短一致，再合并 `Solar.getFestivals()` 支持母亲节/父亲节/感恩节/万圣节等）。
  static String? solarFestival(DateTime date) {
    final cacheKey = (date.year, date.month, date.day);
    final cached = _solarFestivalCache.get(cacheKey);
    if (cached != null) return cached.value;
    String? result = _solarFestivalOverrides['${date.month}-${date.day}'];
    if (result == null) {
      try {
        final festivals = lunar_pkg.Solar.fromYmd(
          date.year,
          date.month,
          date.day,
        ).getFestivals();
        for (final raw in festivals) {
          final normalized = _normalizeSolarFestivalName(raw);
          if (normalized.isNotEmpty) {
            result = normalized;
            break;
          }
        }
      } catch (_) {
        // Ignore out-of-range solar date edge cases.
      }
    }
    _solarFestivalCache.put(cacheKey, _LunarCacheBox(result));
    return result;
  }

  static String _normalizeSolarFestivalName(String raw) {
    return switch (raw.trim()) {
      '元旦节' => '元旦',
      _ => raw.trim(),
    };
  }

  /// 农历节日(按农历月日)，支持动态除夕、寒食节及 `Lunar.getFestivals()` 合并。
  static String? lunarFestival(LunarDate d) {
    // Traditional festivals follow the regular month, not its leap repeat.
    if (d.isLeapMonth) return null;
    final cacheKey = (d.year, d.month, d.day);
    final cached = _lunarFestivalCache.get(cacheKey);
    if (cached != null) return cached.value;

    const t = <String, String>{
      '1-1': '春节',
      '1-15': '元宵',
      '2-2': '龙抬头',
      '5-5': '端午',
      '7-7': '七夕',
      '7-15': '中元',
      '8-15': '中秋',
      '9-9': '重阳',
      '12-8': '腊八',
      '12-23': '小年',
    };
    String? result;
    final k = '${d.month}-${d.day}';
    if (d.month == 12 && d.day >= 29) {
      var finalDay = daysInMonth(d.year, 12);
      try {
        finalDay =
            lunar_pkg.LunarMonth.fromYm(d.year, 12)?.getDayCount() ?? finalDay;
      } catch (_) {
        // Match date conversion's bundled-table fallback.
      }
      if (d.day == finalDay) result = '除夕';
    }
    result ??= t[k];
    if (result == null) {
      try {
        final lunar = lunar_pkg.Lunar.fromYmd(d.year, d.month, d.day);
        for (final raw in lunar.getFestivals()) {
          final normalized = _normalizeLunarFestivalName(raw);
          if (normalized.isNotEmpty) {
            result = normalized;
            break;
          }
        }
        if (result == null) {
          for (final other in lunar.getOtherFestivals()) {
            if (other == '寒食节' || other == '春社' || other == '秋社') {
              result = other;
              break;
            }
          }
        }
      } catch (_) {
        // Synthetic invalid dates (e.g. 12-31) return null safely.
      }
    }
    _lunarFestivalCache.put(cacheKey, _LunarCacheBox(result));
    return result;
  }

  static String _normalizeLunarFestivalName(String raw) {
    return switch (raw.trim()) {
      '元宵节' => '元宵',
      '龙头节' => '龙抬头',
      '端午节' => '端午',
      '七夕节' => '七夕',
      '中元节' => '中元',
      '中秋节' => '中秋',
      '重阳节' => '重阳',
      '腊八节' => '腊八',
      _ => raw.trim(),
    };
  }

  /// 返回某公历日期的全部公历+农历+传统节日名称（去重）。
  static List<String> allFestivals(DateTime date) {
    final seen = <String>{};
    final result = <String>[];
    void addNormalized(String? v) {
      if (v == null || v.isEmpty) return;
      if (seen.add(v)) result.add(v);
    }

    addNormalized(solarFestival(date));
    try {
      final sFests = lunar_pkg.Solar.fromYmd(
        date.year,
        date.month,
        date.day,
      ).getFestivals();
      for (final f in sFests) {
        addNormalized(_normalizeSolarFestivalName(f));
      }
    } catch (_) {}

    final lunar = tryFromSolar(date);
    if (lunar != null && !lunar.isLeapMonth) {
      addNormalized(lunarFestival(lunar));
      try {
        final lObj = _lunarFor(date);
        for (final f in lObj.getFestivals()) {
          addNormalized(_normalizeLunarFestivalName(f));
        }
        for (final f in lObj.getOtherFestivals()) {
          if (f == '寒食节' || f == '春社' || f == '秋社') {
            addNormalized(f);
          }
        }
      } catch (_) {}
    }
    return List.unmodifiable(result);
  }

  /// 黄历"宜"。
  static String suitable(DateTime date) {
    return _suitableForLunar(_lunarFor(date));
  }

  /// 黄历"忌"。
  static String avoid(DateTime date) {
    return _avoidForLunar(_lunarFor(date));
  }

  static String _suitableForLunar(lunar_pkg.Lunar lunar) {
    final value = _joinAlmanacTerms(lunar.getDayYi());
    return value.isEmpty ? '诸事不宜' : value;
  }

  static String _avoidForLunar(lunar_pkg.Lunar lunar) {
    final value = _joinAlmanacTerms(lunar.getDayJi());
    return value.isEmpty ? '无' : value;
  }

  static String _joinAlmanacTerms(List<String> values) => values
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .join(' ');

  static String _monthName(int m, bool isLeap) {
    const names = [
      '正月',
      '二月',
      '三月',
      '四月',
      '五月',
      '六月',
      '七月',
      '八月',
      '九月',
      '十月',
      '冬月',
      '腊月',
    ];
    if (m < 1 || m > 12) return '';
    return '${isLeap ? '闰' : ''}${names[m - 1]}';
  }

  static String _dayName(int d) {
    if (d < 1 || d > 30) return '';
    if (d <= 10) {
      const n = [
        '',
        '初一',
        '初二',
        '初三',
        '初四',
        '初五',
        '初六',
        '初七',
        '初八',
        '初九',
        '初十',
      ];
      return n[d];
    }
    if (d < 20) {
      const n = ['十一', '十二', '十三', '十四', '十五', '十六', '十七', '十八', '十九'];
      return n[d - 11];
    }
    if (d == 20) return '二十';
    if (d < 30) {
      const n = ['廿一', '廿二', '廿三', '廿四', '廿五', '廿六', '廿七', '廿八', '廿九'];
      return n[d - 21];
    }
    return '三十';
  }
}

final class _LunarCacheBox<T> {
  final T value;

  const _LunarCacheBox(this.value);
}

class _LunarLruCache<K, V> {
  final int maxEntries;
  final LinkedHashMap<K, V> _entries = LinkedHashMap<K, V>();

  _LunarLruCache(this.maxEntries);

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
}
