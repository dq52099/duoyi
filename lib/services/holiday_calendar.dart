/// 法定节假日与调休判定服务（Task 21 / Requirements 11.2）。
///
/// 数据策略：
/// - 当前采用内置 JSON（本文件内的 `_kBuiltinHolidays`）覆盖当前年 + 次年。
/// - 预留 [HolidayCalendar.updateFrom] 入口，供未来从后端或 Assets 拉取
///   覆盖式数据（cloud_sync_v2 落地时接入）。
///
/// 语义：
/// - [isHoliday]：当天是否是**法定放假日**（不管是不是周末）。
/// - [isWorkMakeupDay]：当天是否是**周末调休上班日**（例如春节前后的周末补班）。
/// - 未被列入内置数据的日期：周六/周日按惯例视作非法定节假日（`isHoliday=false`）。
///   如需支持"默认把周末也视为假期"，可在调用侧叠加 `weekday >= 6` 的判断。
///
/// 内置数据只覆盖 2024 与 2025；2026 起应通过 [updateFrom] 注入或更新常量。
library;

/// 法定节假日 / 调休上班一年的数据集合。
class HolidayYear {
  /// `MM-DD` 字符串集合。
  final Set<String> holidays;

  /// `MM-DD` 字符串集合（周末调休上班）。
  final Set<String> workMakeupDays;

  const HolidayYear({
    required this.holidays,
    required this.workMakeupDays,
  });
}

/// 2024 / 2025 法定节假日（来源：国务院办公厅公告）。
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
      '02-04', '02-18',
      '04-07', '04-28',
      '05-11',
      '09-14', '09-29',
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
    workMakeupDays: <String>{
      '01-26', '02-08',
      '04-27',
      '09-28',
      '10-11',
    },
  ),
};

/// 节假日服务。线程上下文：全部同步调用，无副作用；后端更新由 [updateFrom]
/// 以**覆盖式** replace 现有条目。
class HolidayCalendar {
  HolidayCalendar._();

  /// 工具类单例，便于上游注入 mock 时用。
  static final HolidayCalendar instance = HolidayCalendar._();

  // 可变覆盖层：`updateFrom` 的数据会进这里，优先于 `_kBuiltinHolidays`。
  static final Map<int, HolidayYear> _overrides = <int, HolidayYear>{};

  /// 当天是否是**法定放假日**。
  static bool isHoliday(DateTime day) {
    final year = _resolve(day.year);
    if (year == null) return false;
    return year.holidays.contains(_mmdd(day));
  }

  /// 当天是否是**调休上班日**（通常是周末）。
  static bool isWorkMakeupDay(DateTime day) {
    final year = _resolve(day.year);
    if (year == null) return false;
    return year.workMakeupDays.contains(_mmdd(day));
  }

  /// 用新数据覆盖指定年份。调用方（cloud_sync_v2 / assets loader）负责
  /// 给出正确的 `year` 与 `HolidayYear` 载荷。
  static void updateFrom(int year, HolidayYear data) {
    _overrides[year] = data;
  }

  /// 清空覆盖层（主要用于测试）。
  static void resetOverrides() {
    _overrides.clear();
  }

  static HolidayYear? _resolve(int year) =>
      _overrides[year] ?? _kBuiltinHolidays[year];

  static String _mmdd(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
