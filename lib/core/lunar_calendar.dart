import 'package:lunar/lunar.dart' as lunar_pkg;

/// 农历(阴历)日期换算工具。
/// 支持 1900-2099 年的公历↔农历转换、节气、干支、生肖、黄历详情。
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

class AlmanacHourFortune {
  final String branch;
  final String range;
  final String deity;
  final bool isAuspicious;

  const AlmanacHourFortune({
    required this.branch,
    required this.range,
    required this.deity,
    required this.isAuspicious,
  });

  String get compactLabel => '$branch${isAuspicious ? '吉' : '凶'}';
}

class LunarAlmanacDetail {
  final String dayGanzhi;
  final String fetalGod;
  final String pengZu;
  final String fiveElements;
  final String mansion;
  final String clash;
  final String hourFortunes;

  const LunarAlmanacDetail({
    required this.dayGanzhi,
    required this.fetalGod,
    required this.pengZu,
    required this.fiveElements,
    required this.mansion,
    required this.clash,
    required this.hourFortunes,
  });
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

  static int daysInMonth(int year, int month, {bool isLeap = false}) {
    if (year < _baseYear || year >= _baseYear + _lunarInfo.length) return 29;
    if (month < 1 || month > 12) return 29;
    if (isLeap && _leapMonth(year) == month) return _leapDays(year);
    return _monthDays(year, month);
  }

  static String monthName(int month, {bool isLeap = false}) =>
      _monthName(month, isLeap);

  static String dayName(int day) => _dayName(day);

  /// 公历 → 农历
  static LunarDate fromSolar(DateTime date) {
    try {
      final lunar = _lunarFor(date);
      final month = lunar.getMonth();
      return LunarDate(
        lunar.getYear(),
        month.abs(),
        lunar.getDay(),
        isLeapMonth: month < 0,
      );
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

  static LunarAlmanacDetail almanacDetail(DateTime date) {
    final lunar = _lunarFor(date);
    return LunarAlmanacDetail(
      dayGanzhi: lunar.getDayInGanZhi(),
      fetalGod: _compactText(lunar.getDayPositionTai()),
      pengZu: '${lunar.getPengZuGan()}；${lunar.getPengZuZhi()}',
      fiveElements: '${lunar.getDayNaYin()}${lunar.getZhiXing()}执位',
      mansion:
          '${_mansionDirection(lunar.getGong())}${lunar.getXiu()}${lunar.getZheng()}${lunar.getAnimal()}-${lunar.getXiuLuck()}',
      clash: _clashText(lunar),
      hourFortunes: hourFortuneSummary(date),
    );
  }

  static String almanacGanzhiLine(DateTime date, LunarDate lunar) {
    final day = _lunarFor(date);
    return '${day.getYearInGanZhi()}${day.getYearShengXiao()}年${day.getMonthInGanZhi()}月${day.getDayInGanZhi()}日';
  }

  static String fetalGod(DateTime date) =>
      _compactText(_lunarFor(date).getDayPositionTai());

  static String pengZu(DateTime date) =>
      '${_lunarFor(date).getPengZuGan()}；${_lunarFor(date).getPengZuZhi()}';

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
    final times = _lunarFor(date).getTimes().take(12).toList();
    return List.generate(times.length, (index) {
      final time = times[index];
      final luck = time.getTianShenLuck();
      return AlmanacHourFortune(
        branch: time.getZhi(),
        range: hourRanges[index],
        deity: time.getTianShen(),
        isAuspicious: luck == '吉',
      );
    });
  }

  static String hourFortuneSummary(DateTime date) =>
      hourFortunes(date).map((item) => item.compactLabel).join(' ');

  static lunar_pkg.Lunar _lunarFor(DateTime date) =>
      lunar_pkg.Lunar.fromDate(DateTime(date.year, date.month, date.day));

  static String _compactText(String value) => value.replaceAll(' ', '');

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

  static int _positiveMod(int value, int mod) {
    final result = value % mod;
    return result < 0 ? result + mod : result;
  }

  /// 是否节气日，返回该日节气名，无则返回 null。
  /// 使用 lunar 库的节气表，和黄历详情保持同源。
  static String? solarTerm(DateTime date) {
    final value = _lunarFor(date).getJieQi();
    return value.isEmpty ? null : value;
  }

  /// 公历法定节日
  static String? solarFestival(DateTime date) {
    const t = <String, String>{
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
    return t['${date.month}-${date.day}'];
  }

  /// 农历节日(按农历月日)
  static String? lunarFestival(LunarDate d) {
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
    final k = '${d.month}-${d.day}';
    if (d.month == 12 && d.day >= 29) return '除夕'; // 简化
    return t[k];
  }

  /// 黄历"宜"。
  static String suitable(DateTime date) {
    final value = _joinAlmanacTerms(_lunarFor(date).getDayYi());
    return value.isEmpty ? '诸事不宜' : value;
  }

  /// 黄历"忌"。
  static String avoid(DateTime date) {
    final value = _joinAlmanacTerms(_lunarFor(date).getDayJi());
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
