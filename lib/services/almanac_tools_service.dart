/// 万年历高级实用工具服务（择吉日查询 / 日期间隔与工作日计算 / 日期加减推算 /
/// 公农历含闰月互转 / 宜忌白话词典）。
///
/// 所有历法与宜忌数据均来自 `lunar: ^1.7.8` 与 [HolidayCalendar] 真实计算。
library;

import '../core/almanac_locale_format.dart';
import '../core/i18n.dart';
import '../core/lunar_calendar.dart';
import 'holiday_calendar.dart';

/// 择吉日查询预设事项。
class AuspiciousActivityPreset {
  /// 标准黄历词条（或别名键），如 `嫁娶`、`入宅`。
  final String key;

  /// 中文展示名（如 `嫁娶 / 结婚`）。
  final String labelZh;

  /// 英文展示名（如 `Marriage`）。
  final String labelEn;

  /// 匹配黄历宜忌时的同义词列表。
  final List<String> matchTerms;

  const AuspiciousActivityPreset({
    required this.key,
    required this.labelZh,
    required this.labelEn,
    required this.matchTerms,
  });

  String localizedLabel([AppLocale? locale]) =>
      (locale ?? I18n.current) == AppLocale.en ? labelEn : labelZh;
}

/// 单条择吉日查询匹配结果。
class AuspiciousDayMatch {
  final DateTime date;
  final LunarDate lunarDate;
  final String lunarLabel;
  final String ganzhiLine;
  final String dayGanzhi;
  final String tianShen;
  final String tianShenType;
  final String tianShenLuck;
  final String zhiXing;
  final String clash;
  final String dayChongShengXiao;
  final List<String> suitableTerms;
  final List<String> avoidTerms;
  final bool isHoliday;
  final bool isWorkMakeupDay;
  final bool isWeekend;
  final bool isRestDay;
  final String? holidayName;
  final String? solarTerm;
  final String? festival;
  final LunarAlmanacDetail detail;

  AuspiciousDayMatch({
    required this.date,
    required this.lunarDate,
    required this.lunarLabel,
    required this.ganzhiLine,
    required this.dayGanzhi,
    required this.tianShen,
    required this.tianShenType,
    required this.tianShenLuck,
    required this.zhiXing,
    required this.clash,
    required this.dayChongShengXiao,
    required List<String> suitableTerms,
    required List<String> avoidTerms,
    required this.isHoliday,
    required this.isWorkMakeupDay,
    required this.isWeekend,
    required this.isRestDay,
    required this.holidayName,
    required this.solarTerm,
    required this.festival,
    required this.detail,
  }) : suitableTerms = List.unmodifiable(suitableTerms),
       avoidTerms = List.unmodifiable(avoidTerms);

  bool get isHuangDao => tianShenType == '黄道';
}

/// 两个日期的间隔计算结果。
class DateIntervalResult {
  final DateTime startDate;
  final DateTime endDate;
  final bool isReversed;
  final bool inclusive;
  final int calendarDays;
  final int signedCalendarDays;
  final int workdays;
  final int restDays;
  final int weekendDays;
  final int holidayDays;
  final int makeupWorkdays;
  final int exactYears;
  final int exactMonths;
  final int exactDays;
  final double approxWeeks;
  final double approxMonths;
  final double approxYears;

  const DateIntervalResult({
    required this.startDate,
    required this.endDate,
    required this.isReversed,
    required this.inclusive,
    required this.calendarDays,
    required this.signedCalendarDays,
    required this.workdays,
    required this.restDays,
    required this.weekendDays,
    required this.holidayDays,
    required this.makeupWorkdays,
    required this.exactYears,
    required this.exactMonths,
    required this.exactDays,
    required this.approxWeeks,
    required this.approxMonths,
    required this.approxYears,
  });
}

/// 日期加减推算结果。
class DateOffsetResult {
  final DateTime baseDate;
  final DateTime targetDate;
  final int deltaDays;
  final bool workdaysOnly;
  final int calendarDaysSpan;
  final LunarDate? lunarDate;
  final String lunarLabel;
  final String? holidayName;
  final bool isHoliday;
  final bool isWorkMakeupDay;
  final bool isWorkday;
  final String xingZuo;
  final int isoWeekNumber;
  final LunarAlmanacDetail? detail;

  const DateOffsetResult({
    required this.baseDate,
    required this.targetDate,
    required this.deltaDays,
    required this.workdaysOnly,
    required this.calendarDaysSpan,
    required this.lunarDate,
    required this.lunarLabel,
    required this.holidayName,
    required this.isHoliday,
    required this.isWorkMakeupDay,
    required this.isWorkday,
    required this.xingZuo,
    required this.isoWeekNumber,
    required this.detail,
  });
}

/// 公农历互转完整结果。
class DateConversionDetail {
  final DateTime solarDate;
  final LunarDate lunarDate;
  final String lunarLabel;
  final String fullLunarLabel;
  final String ganzhiLine;
  final String zodiac;
  final String xingZuo;
  final int isoWeekNumber;
  final int dayOfYear;
  final String tianShen;
  final String tianShenType;
  final String tianShenLuck;
  final String zhiXing;
  final String? solarTerm;
  final String? festival;
  final bool isHoliday;
  final bool isWorkMakeupDay;
  final String? holidayName;
  final LunarAlmanacDetail? detail;

  const DateConversionDetail({
    required this.solarDate,
    required this.lunarDate,
    required this.lunarLabel,
    required this.fullLunarLabel,
    required this.ganzhiLine,
    required this.zodiac,
    required this.xingZuo,
    required this.isoWeekNumber,
    required this.dayOfYear,
    required this.tianShen,
    required this.tianShenType,
    required this.tianShenLuck,
    required this.zhiXing,
    required this.solarTerm,
    required this.festival,
    required this.isHoliday,
    required this.isWorkMakeupDay,
    required this.holidayName,
    required this.detail,
  });
}

/// 宜忌词条白话释义结果。
class AlmanacTermExplanation {
  final String term;
  final String englishTitle;
  final String category;
  final String zhExplanation;
  final String enExplanation;
  final bool english;
  final bool isKnown;

  const AlmanacTermExplanation({
    required this.term,
    required this.englishTitle,
    required this.category,
    required this.zhExplanation,
    required this.enExplanation,
    required this.english,
    required this.isKnown,
  });

  String get explanation => english ? enExplanation : zhExplanation;

  String localizedTitle([AppLocale? locale]) =>
      (locale ?? (english ? AppLocale.en : I18n.current)) == AppLocale.en
      ? englishTitle
      : term;

  String localizedExplanation([AppLocale? locale]) =>
      (locale ?? (english ? AppLocale.en : I18n.current)) == AppLocale.en
      ? enExplanation
      : zhExplanation;
}

class AlmanacToolsService {
  AlmanacToolsService._();

  /// 十二生肖列表（用于择吉避冲筛选）。
  static const List<String> zodiacOptions = <String>[
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

  /// 预设择吉日查询事项（14 项高频场景）。
  static const List<AuspiciousActivityPreset> presetActivities =
      <AuspiciousActivityPreset>[
        AuspiciousActivityPreset(
          key: '嫁娶',
          labelZh: '嫁娶 / 结婚',
          labelEn: 'Marriage / Wedding',
          matchTerms: ['嫁娶'],
        ),
        AuspiciousActivityPreset(
          key: '入宅',
          labelZh: '入宅 / 搬家',
          labelEn: 'Moving In',
          matchTerms: ['入宅', '移徙'],
        ),
        AuspiciousActivityPreset(
          key: '开市',
          labelZh: '开市 / 开业',
          labelEn: 'Grand Opening',
          matchTerms: ['开市'],
        ),
        AuspiciousActivityPreset(
          key: '动土',
          labelZh: '动土 / 装修',
          labelEn: 'Renovation',
          matchTerms: ['动土', '修造'],
        ),
        AuspiciousActivityPreset(
          key: '出行',
          labelZh: '出行',
          labelEn: 'Travel',
          matchTerms: ['出行'],
        ),
        AuspiciousActivityPreset(
          key: '交易',
          labelZh: '交易 / 提车',
          labelEn: 'Trade & Car Pickup',
          matchTerms: ['交易', '买车', '立券交易', '立券'],
        ),
        AuspiciousActivityPreset(
          key: '祈福',
          labelZh: '祈福',
          labelEn: 'Blessing',
          matchTerms: ['祈福'],
        ),
        AuspiciousActivityPreset(
          key: '安床',
          labelZh: '安床',
          labelEn: 'Setting Bed',
          matchTerms: ['安床'],
        ),
        AuspiciousActivityPreset(
          key: '订盟',
          labelZh: '订盟',
          labelEn: 'Engagement Pledge',
          matchTerms: ['订盟', '订婚'],
        ),
        AuspiciousActivityPreset(
          key: '纳采',
          labelZh: '纳采',
          labelEn: 'Betrothal Gifts',
          matchTerms: ['纳采'],
        ),
        AuspiciousActivityPreset(
          key: '祭祀',
          labelZh: '祭祀',
          labelEn: 'Worship',
          matchTerms: ['祭祀'],
        ),
        AuspiciousActivityPreset(
          key: '理发',
          labelZh: '理发',
          labelEn: 'Haircut',
          matchTerms: ['理发', '剃头'],
        ),
        AuspiciousActivityPreset(
          key: '会亲友',
          labelZh: '会亲友',
          labelEn: 'Visiting Family',
          matchTerms: ['会亲友', '会友'],
        ),
        AuspiciousActivityPreset(
          key: '求医',
          labelZh: '求医',
          labelEn: 'Medical Care',
          matchTerms: ['求医', '治病', '求医疗病'],
        ),
      ];

  static const Map<String, List<String>> _activityAliases =
      <String, List<String>>{
        '嫁娶': ['嫁娶'],
        '结婚': ['嫁娶'],
        '嫁娶/结婚': ['嫁娶'],
        '入宅': ['入宅', '移徙'],
        '搬家': ['入宅', '移徙'],
        '入宅/搬家': ['入宅', '移徙'],
        '乔迁': ['入宅', '移徙'],
        '开市': ['开市'],
        '开业': ['开市'],
        '开张': ['开市'],
        '开市/开业': ['开市'],
        '动土': ['动土', '修造'],
        '装修': ['动土', '修造'],
        '动土/装修': ['动土', '修造'],
        '出行': ['出行'],
        '旅游': ['出行'],
        '远行': ['出行'],
        '交易': ['交易', '立券交易', '立券', '买车'],
        '提车': ['交易', '买车', '立券交易'],
        '交易/提车': ['交易', '买车', '立券交易', '立券'],
        '签约': ['立券', '立券交易', '交易'],
        '订婚': ['订婚', '订盟', '纳采'],
        '求医': ['求医', '治病', '求医疗病'],
        '理发': ['理发', '剃头'],
      };

  /// 择吉日查询。
  static List<AuspiciousDayMatch> findAuspiciousDays({
    required String activity,
    required DateTime startDate,
    int rangeDays = 90,
    bool weekendsOrHolidaysOnly = false,
    String? avoidZodiac,
  }) {
    final query = activity.trim();
    if (query.isEmpty || rangeDays <= 0) return const [];

    final clampedDays = rangeDays.clamp(1, 730);
    final matchTargets = _resolveActivityTargets(query);
    final avoidZ = avoidZodiac?.trim();
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final results = <AuspiciousDayMatch>[];

    for (var offset = 0; offset < clampedDays; offset++) {
      final candidate = DateTime(start.year, start.month, start.day + offset);
      if (!LunarCalendar.isWithinDocumentedSolarRange(candidate)) continue;

      final isHoliday = HolidayCalendar.isHoliday(candidate);
      final isMakeup = HolidayCalendar.isWorkMakeupDay(candidate);
      final isWeekend =
          candidate.weekday == DateTime.saturday ||
          candidate.weekday == DateTime.sunday;
      final isRestDay = HolidayCalendar.isRestDay(candidate);

      if (weekendsOrHolidaysOnly && !isRestDay) {
        continue;
      }

      final detail = LunarCalendar.tryAlmanacDetail(candidate);
      if (detail == null) continue;

      if (avoidZ != null &&
          avoidZ.isNotEmpty &&
          detail.dayChongShengXiao == avoidZ) {
        continue;
      }

      final suitableTerms = _splitTerms(detail.suitable);
      final avoidTerms = _splitTerms(detail.avoid);

      if (suitableTerms.isEmpty || suitableTerms.contains('诸事不宜')) {
        continue;
      }

      final hasMatch = _matchesActivity(suitableTerms, matchTargets, query);
      if (!hasMatch) continue;

      final isExplicitlyAvoided = _matchesActivity(
        avoidTerms,
        matchTargets,
        query,
      );
      if (isExplicitlyAvoided) continue;

      final solarFes = LunarCalendar.solarFestival(candidate);
      final lunarFes = LunarCalendar.lunarFestival(detail.lunarDate);

      results.add(
        AuspiciousDayMatch(
          date: candidate,
          lunarDate: detail.lunarDate,
          lunarLabel: detail.lunarDate.chineseText,
          ganzhiLine: detail.ganzhiLine,
          dayGanzhi: detail.dayGanzhi,
          tianShen: detail.tianShen,
          tianShenType: detail.tianShenType,
          tianShenLuck: detail.tianShenLuck,
          zhiXing: detail.zhiXing,
          clash: detail.clash,
          dayChongShengXiao: detail.dayChongShengXiao,
          suitableTerms: suitableTerms,
          avoidTerms: avoidTerms,
          isHoliday: isHoliday,
          isWorkMakeupDay: isMakeup,
          isWeekend: isWeekend,
          isRestDay: isRestDay,
          holidayName: HolidayCalendar.holidayName(candidate),
          solarTerm: detail.currentSolarTerm,
          festival: solarFes ?? lunarFes,
          detail: detail,
        ),
      );
    }

    return List.unmodifiable(results);
  }

  /// 计算两日期之间的自然日、法定工作日、周末、法定假日及调休补班天数。
  static DateIntervalResult calculateDateInterval(
    DateTime start,
    DateTime end, {
    bool inclusive = false,
  }) {
    final s = DateTime(start.year, start.month, start.day);
    final e = DateTime(end.year, end.month, end.day);
    final isReversed = e.isBefore(s);
    final early = isReversed ? e : s;
    final late = isReversed ? s : e;

    final earlyUtc = DateTime.utc(early.year, early.month, early.day);
    final lateUtc = DateTime.utc(late.year, late.month, late.day);
    final rawDiff = lateUtc.difference(earlyUtc).inDays;
    final signedDiff = DateTime.utc(e.year, e.month, e.day)
        .difference(DateTime.utc(s.year, s.month, s.day))
        .inDays;

    final spanCount = inclusive ? rawDiff + 1 : rawDiff;
    int workdays = 0;
    int weekendDays = 0;
    int holidayDays = 0;
    int makeupWorkdays = 0;

    for (var i = 0; i < spanCount; i++) {
      final d = DateTime(early.year, early.month, early.day + i);
      if (d.weekday == DateTime.saturday || d.weekday == DateTime.sunday) {
        weekendDays++;
      }
      if (HolidayCalendar.isHoliday(d)) {
        holidayDays++;
      } else if (HolidayCalendar.isWorkMakeupDay(d)) {
        makeupWorkdays++;
      }
      if (HolidayCalendar.isWorkday(d)) {
        workdays++;
      }
    }

    final (exactY, exactM, exactD) = _exactCalendarYmdDiff(early, late);

    return DateIntervalResult(
      startDate: s,
      endDate: e,
      isReversed: isReversed,
      inclusive: inclusive,
      calendarDays: spanCount,
      signedCalendarDays: signedDiff,
      workdays: workdays,
      restDays: spanCount - workdays,
      weekendDays: weekendDays,
      holidayDays: holidayDays,
      makeupWorkdays: makeupWorkdays,
      exactYears: exactY,
      exactMonths: exactM,
      exactDays: exactD,
      approxWeeks: spanCount / 7.0,
      approxMonths: spanCount / 30.4375,
      approxYears: spanCount / 365.2425,
    );
  }

  /// 日期加减推算（支持自然日或结合法定节假日/调休的工作日推算）。
  static DateOffsetResult offsetDate(
    DateTime base,
    int deltaDays, {
    bool workdaysOnly = false,
  }) {
    final start = DateTime(base.year, base.month, base.day);
    DateTime target = start;
    if (deltaDays != 0) {
      if (!workdaysOnly) {
        target = DateTime(start.year, start.month, start.day + deltaDays);
      } else {
        var remaining = deltaDays.abs();
        final step = deltaDays > 0 ? 1 : -1;
        while (remaining > 0) {
          target = DateTime(target.year, target.month, target.day + step);
          if (HolidayCalendar.isWorkday(target)) {
            remaining--;
          }
        }
      }
    }

    final span = DateTime.utc(target.year, target.month, target.day)
        .difference(DateTime.utc(start.year, start.month, start.day))
        .inDays;
    final lunar = LunarCalendar.tryFromSolar(target);
    final detail = LunarCalendar.tryAlmanacDetail(target);

    return DateOffsetResult(
      baseDate: start,
      targetDate: target,
      deltaDays: deltaDays,
      workdaysOnly: workdaysOnly,
      calendarDaysSpan: span,
      lunarDate: lunar,
      lunarLabel: lunar?.chineseText ?? '',
      holidayName: HolidayCalendar.holidayName(target),
      isHoliday: HolidayCalendar.isHoliday(target),
      isWorkMakeupDay: HolidayCalendar.isWorkMakeupDay(target),
      isWorkday: HolidayCalendar.isWorkday(target),
      xingZuo: LunarCalendar.xingZuo(target),
      isoWeekNumber: LunarCalendar.isoWeekNumber(target),
      detail: detail,
    );
  }

  /// 公历转农历完整详情。
  static DateConversionDetail? solarToLunarDetail(DateTime date) {
    final solar = DateTime(date.year, date.month, date.day);
    final lunar = LunarCalendar.tryFromSolar(solar);
    if (lunar == null) return null;
    final detail = LunarCalendar.tryAlmanacDetail(solar);
    final solarFes = LunarCalendar.solarFestival(solar);
    final lunarFes = LunarCalendar.lunarFestival(lunar);
    return DateConversionDetail(
      solarDate: solar,
      lunarDate: lunar,
      lunarLabel: lunar.chineseText,
      fullLunarLabel: AlmanacLocaleFormat.formatFullLunarDate(
        lunar,
        includeGanzhi: true,
        locale: AppLocale.zh,
      ),
      ganzhiLine: detail?.ganzhiLine ?? LunarCalendar.almanacGanzhiLine(solar, lunar),
      zodiac: detail?.yearZodiac ?? LunarCalendar.zodiacOf(lunar.year),
      xingZuo: detail?.xingZuo ?? LunarCalendar.xingZuo(solar),
      isoWeekNumber: detail?.isoWeekNumber ?? LunarCalendar.isoWeekNumber(solar),
      dayOfYear: detail?.dayOfYear ?? LunarCalendar.dayOfYear(solar),
      tianShen: detail?.tianShen ?? '',
      tianShenType: detail?.tianShenType ?? '',
      tianShenLuck: detail?.tianShenLuck ?? '',
      zhiXing: detail?.zhiXing ?? '',
      solarTerm: detail?.currentSolarTerm ?? LunarCalendar.solarTerm(solar),
      festival: solarFes ?? lunarFes,
      isHoliday: HolidayCalendar.isHoliday(solar),
      isWorkMakeupDay: HolidayCalendar.isWorkMakeupDay(solar),
      holidayName: HolidayCalendar.holidayName(solar),
      detail: detail,
    );
  }

  /// 农历转公历完整详情（严格支持闰月；非法闰月或超出天数返回 `null`）。
  static DateConversionDetail? lunarToSolarDetail(
    int year,
    int month,
    int day, {
    bool isLeap = false,
  }) {
    final solar = LunarCalendar.tryToSolar(year, month, day, isLeap: isLeap);
    if (solar == null) return null;
    return solarToLunarDetail(solar);
  }

  /// 宜忌白话词典（覆盖 100+ 常见与传统词条，提供现代白话双语释义）。
  static AlmanacTermExplanation explainAlmanacTerm(
    String term, {
    bool english = false,
  }) {
    final key = term.trim();
    final entry = _plainDictionary[key];
    final enTitle = AlmanacLocaleFormat.formatActivityTerm(key, AppLocale.en);
    if (entry != null) {
      return AlmanacTermExplanation(
        term: key,
        englishTitle: enTitle,
        category: entry.category,
        zhExplanation: entry.zh,
        enExplanation: entry.en,
        english: english,
        isKnown: true,
      );
    }
    return AlmanacTermExplanation(
      term: key,
      englishTitle: enTitle,
      category: english ? 'Traditional Almanac' : '传统黄历',
      zhExplanation: '传统黄历术语「$key」，建议结合自身实际情况安排。',
      enExplanation:
          'Traditional almanac term "$enTitle"; consider practical conditions when scheduling.',
      english: english,
      isKnown: false,
    );
  }

  static List<String> _resolveActivityTargets(String raw) {
    final normalized = raw.replaceAll(' ', '');
    if (_activityAliases.containsKey(normalized)) {
      return _activityAliases[normalized]!;
    }
    for (final preset in presetActivities) {
      if (preset.key == normalized ||
          preset.labelZh.replaceAll(' ', '') == normalized ||
          preset.labelEn.toLowerCase() == raw.trim().toLowerCase()) {
        return preset.matchTerms;
      }
    }
    return <String>[raw.trim()];
  }

  static List<String> _splitTerms(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed == '无') return const [];
    return trimmed
        .split(RegExp(r'\s+'))
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList(growable: false);
  }

  static bool _matchesActivity(
    List<String> terms,
    List<String> targets,
    String rawQuery,
  ) {
    final lowerQuery = rawQuery.toLowerCase();
    for (final term in terms) {
      for (final target in targets) {
        if (term == target || term.contains(target)) {
          return true;
        }
      }
      final enTerm = AlmanacLocaleFormat.formatActivityTerm(term, AppLocale.en);
      if (enTerm.toLowerCase().contains(lowerQuery)) {
        return true;
      }
    }
    return false;
  }

  static (int, int, int) _exactCalendarYmdDiff(DateTime early, DateTime late) {
    var years = late.year - early.year;
    var months = late.month - early.month;
    var days = late.day - early.day;
    if (days < 0) {
      final prevMonthEnd = DateTime(late.year, late.month, 0);
      days += prevMonthEnd.day;
      months--;
    }
    if (months < 0) {
      months += 12;
      years--;
    }
    return (years, months, days);
  }

  // ---------------------------------------------------------------------------
  // Plain-language dictionary (100+ common & classical Yi/Ji terms)
  // ---------------------------------------------------------------------------
  static const Map<String, ({String category, String zh, String en})>
  _plainDictionary = <String, ({String category, String zh, String en})>{
    '祭祀': (
      category: '民俗礼仪',
      zh: '祭拜祖先、神明或举行追思悼念仪式。',
      en: 'Honoring ancestors, deities, or holding memorial ceremonies.',
    ),
    '祈福': (
      category: '民俗礼仪',
      zh: '祈求平安顺遂、许愿或参加祝愿祈祷活动。',
      en: 'Praying for peace, good fortune, or making positive wishes.',
    ),
    '求嗣': (
      category: '民俗礼仪',
      zh: '祈求添丁或寄托家宅人丁兴旺的心愿。',
      en: 'Praying for children and family continuity.',
    ),
    '开光': (
      category: '民俗礼仪',
      zh: '为神像、佛像或吉祥摆件举行启灵仪式。',
      en: 'Consecrating statues, spiritual objects, or auspicious charms.',
    ),
    '塑绘': (
      category: '民俗礼仪',
      zh: '雕塑或绘制神佛像、传统艺术造像。',
      en: 'Sculpting or painting religious and traditional artwork.',
    ),
    '齐醮': (
      category: '民俗礼仪',
      zh: '道教传统设坛祈禳仪式（同“斋醮”）。',
      en: 'Traditional Taoist altar ceremony for blessings and harmony.',
    ),
    '斋醮': (
      category: '民俗礼仪',
      zh: '洁净身心、设坛诵经以祈福消灾的传统仪典。',
      en: 'Taoist purification and blessing liturgy.',
    ),
    '沐浴': (
      category: '日常起居',
      zh: '清洁洗浴、斋戒净身，或泡温泉放松身心。',
      en: 'Bathing, cleansing, or taking a restorative soak.',
    ),
    '酬神': (
      category: '民俗礼仪',
      zh: '愿望实现后答谢神明恩泽（还愿）。',
      en: 'Giving thanks after a prayer or wish is fulfilled.',
    ),
    '造庙': (
      category: '营造工程',
      zh: '建造或修缮庙宇、祠堂等场所。',
      en: 'Constructing or restoring temples and ancestral halls.',
    ),
    '祀灶': (
      category: '民俗礼仪',
      zh: '祭拜灶王爷，祈求家里衣食丰足、烟火兴旺。',
      en: 'Honoring the Kitchen God for household abundance.',
    ),
    '焚香': (
      category: '民俗礼仪',
      zh: '点香礼敬、静心冥想或营造清净氛围。',
      en: 'Lighting incense for mindfulness, respect, or prayer.',
    ),
    '谢土': (
      category: '营造工程',
      zh: '房屋装修或建筑完工后酬谢土地神的仪式。',
      en: 'Gratitude ceremony upon completing construction or renovation.',
    ),
    '出火': (
      category: '居家生活',
      zh: '搬家前移出家中神位或香火，象征过渡新居。',
      en: 'Relocating a household altar or symbolic hearth before moving.',
    ),
    '雕刻': (
      category: '手艺创作',
      zh: '制作木雕、石雕、印章或精细手工雕刻。',
      en: 'Carving wood, stone, seals, or fine craftwork.',
    ),
    '嫁娶': (
      category: '婚恋喜庆',
      zh: '举办婚礼、迎亲、登记结婚等喜庆大事。',
      en: 'Getting married, holding a wedding ceremony, or registering marriage.',
    ),
    '订婚': (
      category: '婚恋喜庆',
      zh: '双方家庭正式约定婚约、交换信物。',
      en: 'Formal engagement and commitment between two families.',
    ),
    '纳采': (
      category: '婚恋喜庆',
      zh: '男方下聘礼提亲，相当于现代的正式下聘。',
      en: 'Presenting betrothal gifts and formal marriage proposal.',
    ),
    '问名': (
      category: '婚恋喜庆',
      zh: '婚前双方正式互通姓名生辰、确认婚约意向。',
      en: 'Exchanging names and birth details during marriage arrangements.',
    ),
    '纳婿': (
      category: '婚恋喜庆',
      zh: '女方家招婿成婚的相关礼俗。',
      en: 'Welcoming a son-in-law into the bride’s household.',
    ),
    '归宁': (
      category: '婚恋喜庆',
      zh: '新婚后回门探望女方父母（现代泛指回娘家）。',
      en: 'Newlyweds visiting the bride’s parents after marriage.',
    ),
    '安床': (
      category: '居家生活',
      zh: '新婚铺床、购置新床或调整卧室床位摆放。',
      en: 'Setting up a new bed or rearranging bedroom bed placement.',
    ),
    '合帐': (
      category: '居家生活',
      zh: '制作或挂设蚊帐、窗帘及卧室软装布置。',
      en: 'Hanging bed curtains, drapes, or soft bedroom furnishings.',
    ),
    '冠笄': (
      category: '民俗礼仪',
      zh: '传统成人礼，象征少年男女步入成年阶段。',
      en: 'Traditional coming-of-age ceremony.',
    ),
    '订盟': (
      category: '婚恋喜庆',
      zh: '定亲订约、签订重要个人或合作盟约。',
      en: 'Making a betrothal pledge or formal personal commitment.',
    ),
    '进人口': (
      category: '居家生活',
      zh: '家中迎来新成员、收养子女或雇请住家帮手。',
      en: 'Welcoming a new household member or live-in helper.',
    ),
    '裁衣': (
      category: '日常起居',
      zh: '裁剪制作新衣服，或为重要场合定制服饰。',
      en: 'Tailoring new clothes or preparing formal attire.',
    ),
    '挽面': (
      category: '日常起居',
      zh: '传统面部修容（开脸），现代可理解为美容护肤。',
      en: 'Traditional facial grooming; modern beauty and skincare.',
    ),
    '开容': (
      category: '日常起居',
      zh: '梳妆美容、仪容整理与形象打理。',
      en: 'Cosmetic grooming and personal appearance care.',
    ),
    '修坟': (
      category: '殡葬祭扫',
      zh: '修葺、维护先人墓地与坟茔环境。',
      en: 'Repairing or maintaining ancestral tombs.',
    ),
    '启钻': (
      category: '殡葬祭扫',
      zh: '拾骨迁葬或打开旧墓进行修缮。',
      en: 'Opening an older tomb for relocation or restoration.',
    ),
    '破土': (
      category: '殡葬祭扫',
      zh: '专指安葬挖墓穴动土（注：建房装修看“动土”）。',
      en: 'Breaking ground specifically for burial (use Earth-breaking for construction).',
    ),
    '安葬': (
      category: '殡葬祭扫',
      zh: '举行落葬入土仪式、安置骨灰或墓位。',
      en: 'Conducting burial or interment rites.',
    ),
    '立碑': (
      category: '殡葬祭扫',
      zh: '竖立墓碑或纪念石碑。',
      en: 'Erecting a tombstone or memorial monument.',
    ),
    '成服': (
      category: '殡葬祭扫',
      zh: '丧礼期间穿上孝服致哀。',
      en: 'Putting on formal mourning attire.',
    ),
    '除服': (
      category: '殡葬祭扫',
      zh: '守孝期满脱去丧服、恢复日常作息。',
      en: 'Concluding mourning attire and returning to normal life.',
    ),
    '入殓': (
      category: '殡葬祭扫',
      zh: '将逝者安置入棺的传统礼俗。',
      en: 'Placing the deceased into the coffin.',
    ),
    '移柩': (
      category: '殡葬祭扫',
      zh: '出殡前移动灵柩至告别或下葬地点。',
      en: 'Moving the coffin before the funeral procession.',
    ),
    '入宅': (
      category: '居家生活',
      zh: '乔迁入住新房子，正式在新居开火生活。',
      en: 'Moving into a new house and settling in.',
    ),
    '安香': (
      category: '民俗礼仪',
      zh: '在新居安放神龛或香炉供奉。',
      en: 'Setting up a home incense altar.',
    ),
    '安门': (
      category: '营造工程',
      zh: '安装或更换入户大门、院门或室内门扇。',
      en: 'Installing or replacing main doors and entrance gates.',
    ),
    '修造': (
      category: '营造工程',
      zh: '房屋修缮、旧房翻新或较大规模的装修施工。',
      en: 'House remodeling, structural repairs, or major renovation.',
    ),
    '起基': (
      category: '营造工程',
      zh: '新建房屋前打地基、奠定建筑基础。',
      en: 'Laying the structural foundation for a building.',
    ),
    '动土': (
      category: '营造工程',
      zh: '建筑施工开挖第一铲土，现代也指装修正式开工。',
      en: 'Groundbreaking for construction or starting home renovation.',
    ),
    '上梁': (
      category: '营造工程',
      zh: '建房安装主屋脊梁，现代装修亦指主体封顶。',
      en: 'Raising the main roof ridge beam or topping out structure.',
    ),
    '竖柱': (
      category: '营造工程',
      zh: '建房立起主要承重木柱或立柱框架。',
      en: 'Erecting main supporting pillars or framing.',
    ),
    '拆卸': (
      category: '营造工程',
      zh: '拆除旧建筑、旧隔断墙体或旧设施。',
      en: 'Demolishing old structures, partitions, or fixtures.',
    ),
    '破屋': (
      category: '营造工程',
      zh: '拆除旧屋或破除闲置危房。',
      en: 'Tearing down an old or dilapidated building.',
    ),
    '坏垣': (
      category: '营造工程',
      zh: '拆除围墙、隔断墙以进行改造。',
      en: 'Demolishing walls or courtyard fences for remodeling.',
    ),
    '补垣': (
      category: '营造工程',
      zh: '修补墙体裂缝、围墙加固或堵塞缺口。',
      en: 'Repairing damaged walls or reinforcing fences.',
    ),
    '作灶': (
      category: '居家生活',
      zh: '砌筑或安装厨房炉灶、灶台与燃气灶具。',
      en: 'Building or installing kitchen stoves and cooking ranges.',
    ),
    '解除': (
      category: '日常起居',
      zh: '大扫除、祛除晦气或解决长期累积的烦恼。',
      en: 'Deep cleansing, clearing bad luck, or resolving lingering issues.',
    ),
    '盖屋': (
      category: '营造工程',
      zh: '修建屋顶、搭建房舍或遮阳棚屋。',
      en: 'Roofing or constructing a house.',
    ),
    '造仓': (
      category: '营造工程',
      zh: '建造储藏室、仓库或谷仓。',
      en: 'Building a storage room, granary, or warehouse.',
    ),
    '塞穴': (
      category: '居家生活',
      zh: '填堵鼠洞、蚁穴、墙缝或地面孔洞。',
      en: 'Sealing holes, cracks, or rodent burrows.',
    ),
    '平治道涂': (
      category: '营造工程',
      zh: '修整道路、铺平路面或清理出行通道。',
      en: 'Paving, leveling roads, or clearing pathways.',
    ),
    '造桥': (
      category: '营造工程',
      zh: '修建桥梁或铺设人行过道。',
      en: 'Building bridges or pedestrian walkways.',
    ),
    '筑堤': (
      category: '营造工程',
      zh: '修建防洪堤坝或院落挡土墙。',
      en: 'Constructing embankments, dykes, or retaining walls.',
    ),
    '开池': (
      category: '营造工程',
      zh: '挖掘池塘、鱼池或园林水景。',
      en: 'Digging a pond or garden water feature.',
    ),
    '伐木': (
      category: '营造工程',
      zh: '砍伐树木或修剪大型枝干。',
      en: 'Felling timber or heavy tree pruning.',
    ),
    '开渠': (
      category: '营造工程',
      zh: '开挖水渠、排水沟或铺设排水管道。',
      en: 'Digging irrigation ditches or drainage channels.',
    ),
    '掘井': (
      category: '营造工程',
      zh: '打井取水或开凿地下水源。',
      en: 'Digging a water well.',
    ),
    '扫舍': (
      category: '居家生活',
      zh: '清扫房间、居家整理与大扫除。',
      en: 'Sweeping, tidying, and general house cleaning.',
    ),
    '放水': (
      category: '农事工程',
      zh: '引水灌溉农田或疏通清理排水。',
      en: 'Releasing water for irrigation or draining.',
    ),
    '造屋': (
      category: '营造工程',
      zh: '新建住宅房屋或搭建主体建筑。',
      en: 'Constructing a new residential building.',
    ),
    '合脊': (
      category: '营造工程',
      zh: '安装屋顶正脊，象征建房主结构合拢。',
      en: 'Completing the central roof ridge.',
    ),
    '修门': (
      category: '居家生活',
      zh: '修理门锁、门框或门扇保养。',
      en: 'Repairing doors, frames, or locks.',
    ),
    '修饰垣墙': (
      category: '营造工程',
      zh: '粉刷墙壁、刮腻子、贴壁纸等墙面美化。',
      en: 'Plastering, painting, or finishing interior and exterior walls.',
    ),
    '架马': (
      category: '营造工程',
      zh: '施工时搭设脚手架或作业平台。',
      en: 'Erecting scaffolding for construction or maintenance.',
    ),
    '开市': (
      category: '商业财运',
      zh: '店铺开业、公司开张、新项目启动或新年开工。',
      en: 'Grand opening of a shop, company launch, or starting business.',
    ),
    '挂匾': (
      category: '商业财运',
      zh: '悬挂店铺招牌、企业匾额或门牌。',
      en: 'Hanging a shop sign, company plaque, or nameplate.',
    ),
    '纳财': (
      category: '商业财运',
      zh: '收款进账、购置资产、理财入库或收取货款。',
      en: 'Receiving income, collecting payments, or acquiring assets.',
    ),
    '求财': (
      category: '商业财运',
      zh: '开展商务洽谈、开拓财源、投资理财。',
      en: 'Pursuing business revenue, deals, or financial growth.',
    ),
    '开仓': (
      category: '商业财运',
      zh: '打开仓库出货盘点或调拨物资。',
      en: 'Opening warehouses for inventory or dispatching goods.',
    ),
    '买车': (
      category: '商业财运',
      zh: '购买汽车、电动车等交通工具或办理提车手续。',
      en: 'Buying a car or taking delivery of a new vehicle.',
    ),
    '置产': (
      category: '商业财运',
      zh: '买房置业、购置土地或大宗固定资产。',
      en: 'Purchasing real estate or major property assets.',
    ),
    '雇佣': (
      category: '商业财运',
      zh: '招聘员工、签约用工或聘请专业服务人员。',
      en: 'Hiring staff, onboarding employees, or engaging contractors.',
    ),
    '出货财': (
      category: '商业财运',
      zh: '批发发货、大宗货物出库交付。',
      en: 'Shipping commercial inventory and fulfilling orders.',
    ),
    '安机械': (
      category: '工业生产',
      zh: '安装大型机器设备、产线调试或添置器材。',
      en: 'Installing machinery, equipment, or production tools.',
    ),
    '经络': (
      category: '手艺创作',
      zh: '纺织织布、布线整理；中草药调理脉络。',
      en: 'Weaving textiles or organizing intricate threads/lines.',
    ),
    '酝酿': (
      category: '日常起居',
      zh: '酿酒制醋、发酵食品或筹划酝酿重要计划。',
      en: 'Brewing, fermenting food, or carefully incubating plans.',
    ),
    '栽种': (
      category: '农事园艺',
      zh: '播种、移栽花草绿植或果树农作物。',
      en: 'Planting flowers, trees, or sowing crops.',
    ),
    '取渔': (
      category: '农事园艺',
      zh: '捕鱼、垂钓或收获水产。',
      en: 'Fishing or harvesting aquatic catch.',
    ),
    '牧养': (
      category: '农事园艺',
      zh: '饲养宠物、家禽家畜或照料动物。',
      en: 'Raising livestock, poultry, or caring for animals.',
    ),
    '习艺': (
      category: '学习成长',
      zh: '学习才艺、钻研专业技能或参加培训课程。',
      en: 'Learning crafts, practicing arts, or skill training.',
    ),
    '入学': (
      category: '学习成长',
      zh: '新生开学报道、拜师学艺或开启新学业阶段。',
      en: 'Starting school, enrollment, or beginning formal study.',
    ),
    '理发': (
      category: '日常起居',
      zh: '剪头发、修剪胡须或做造型换新面貌。',
      en: 'Getting a haircut, styling hair, or fresh grooming.',
    ),
    '探病': (
      category: '人际社交',
      zh: '前往医院或家中探望生病的亲友。',
      en: 'Visiting sick friends or relatives.',
    ),
    '见贵': (
      category: '人际社交',
      zh: '拜访长辈、领导、客户或重要合作伙伴。',
      en: 'Meeting elders, mentors, clients, or influential people.',
    ),
    '乘船': (
      category: '出行交通',
      zh: '搭乘轮船渡轮出行或水上乘舟游览。',
      en: 'Traveling by boat, ferry, or cruise.',
    ),
    '渡水': (
      category: '出行交通',
      zh: '乘船跨江渡海或涉水通行。',
      en: 'Crossing rivers, lakes, or sea routes.',
    ),
    '针灸': (
      category: '健康医疗',
      zh: '进行中医针灸、艾灸或穴位理疗。',
      en: 'Receiving acupuncture, moxibustion, or traditional therapy.',
    ),
    '出行': (
      category: '出行交通',
      zh: '出差、旅游、自驾远行或启程出发。',
      en: 'Departing for travel, business trips, or long journeys.',
    ),
    '移徙': (
      category: '居家生活',
      zh: '搬家换住处、办公室搬迁或更换生活环境。',
      en: 'Relocating home, moving offices, or changing residence.',
    ),
    '分居': (
      category: '居家生活',
      zh: '大家庭分户独立居住，各自立户过日子。',
      en: 'Setting up separate households within an extended family.',
    ),
    '剃头': (
      category: '日常起居',
      zh: '剃发理发（常指婴儿满月剃胎发或光头修剪）。',
      en: 'Shaving hair (including traditional baby hair-shaving rites).',
    ),
    '整手足甲': (
      category: '日常起居',
      zh: '修剪手指甲、脚趾甲及手足护理。',
      en: 'Trimming fingernails/toenails and hand/foot care.',
    ),
    '纳畜': (
      category: '农事园艺',
      zh: '领养宠物、购入家畜或添置养殖动物。',
      en: 'Adopting pets or acquiring livestock.',
    ),
    '捕捉': (
      category: '农事园艺',
      zh: '捕抓害虫、巡查防护或清理蚊鼠。',
      en: 'Catching pests or protecting property.',
    ),
    '畋猎': (
      category: '农事园艺',
      zh: '传统野外围猎活动。',
      en: 'Traditional field hunting.',
    ),
    '会亲友': (
      category: '人际社交',
      zh: '邀请亲戚朋友聚餐、叙旧或联络感情。',
      en: 'Gathering with relatives and close friends.',
    ),
    '赴任': (
      category: '职场晋升',
      zh: '入职新岗位、调任履新或正式就职上任。',
      en: 'Starting a new job, taking office, or assuming a new post.',
    ),
    '求医': (
      category: '健康医疗',
      zh: '挂号看病、体检问诊或寻求医疗治疗。',
      en: 'Seeing a doctor, medical checkups, or seeking treatment.',
    ),
    '治病': (
      category: '健康医疗',
      zh: '服药调理、手术治疗或康复疗养。',
      en: 'Undergoing medical treatment, surgery, or recovery.',
    ),
    '词讼': (
      category: '事务纠纷',
      zh: '打官司、申请仲裁或处理法律诉讼事务。',
      en: 'Filing lawsuits, legal disputes, or arbitration.',
    ),
    '立券交易': (
      category: '商业财运',
      zh: '签署商业合同、交易买卖、订立契约协议。',
      en: 'Signing contracts, deeds, and completing commercial deals.',
    ),
    '交易': (
      category: '商业财运',
      zh: '买卖商品、达成合作交易或办理过户手续。',
      en: 'Buying, selling, trading, or closing business transactions.',
    ),
    '立券': (
      category: '商业财运',
      zh: '签字立契、订立借据或各类正式合同。',
      en: 'Signing written agreements, leases, or formal contracts.',
    ),
    '会友': (
      category: '人际社交',
      zh: '约见朋友小聚、交流畅谈。',
      en: 'Meeting friends for conversation and catching up.',
    ),
    '求医疗病': (
      category: '健康医疗',
      zh: '寻医问药、诊治疾病与健康调养。',
      en: 'Seeking medical consultation and treatment.',
    ),
    '断蚁': (
      category: '居家生活',
      zh: '防治白蚁、驱除蚁虫害。',
      en: 'Termite and household insect pest control.',
    ),
    '行丧': (
      category: '殡葬祭扫',
      zh: '举行送葬、出殡及追悼仪式。',
      en: 'Conducting funeral processions and farewell rites.',
    ),
    '诸事不宜': (
      category: '综合提示',
      zh: '当日气场欠佳，大事建议另择吉日，适合静养休息。',
      en: 'Generally unfavorable for major undertakings; better for rest and routine.',
    ),
    '馀事勿取': (
      category: '综合提示',
      zh: '除当天“宜”中列出的事项外，其他重大事情暂缓办理。',
      en: 'Stick only to listed favorable items and defer other major plans.',
    ),
    '无': (
      category: '综合提示',
      zh: '当日无特别禁忌或无特别推荐事项。',
      en: 'No special restrictions or entries for this category.',
    ),
  };
}
