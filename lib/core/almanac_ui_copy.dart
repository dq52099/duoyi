/// Almanac UI localization copy (Task: Almanac consumer pass + Full P0/P1/P2 upgrade).
library;

import '../services/holiday_calendar.dart';
import 'almanac_locale_format.dart';
import 'i18n.dart';
import 'i18n_date_format.dart';
import 'lunar_calendar.dart';

class AlmanacUiCopy {
  AlmanacUiCopy._();

  static bool get isEn => I18n.current == AppLocale.en;
  static bool get isZh => I18n.current == AppLocale.zh;

  // ---------------------------------------------------------------------------
  // Page titles & tooltips
  // ---------------------------------------------------------------------------
  static String get pageTitle => isEn ? 'Almanac' : '万年历';
  static String get previousDayTooltip => isEn ? 'Previous day' : '前一天';
  static String get nextDayTooltip => isEn ? 'Next day' : '后一天';
  static String get todayTooltip => isEn ? 'Today' : '回到今天';
  static String get previousMonthTooltip => isEn ? 'Previous month' : '上个月';
  static String get nextMonthTooltip => isEn ? 'Next month' : '下个月';
  static String get backTooltip => isEn ? 'Back' : '返回';
  static String get selectDateTooltip => isEn ? 'Select date' : '选择日期';
  static String get viewAlmanacDetail =>
      isEn ? 'View almanac details' : '查看黄历详情';

  // ---------------------------------------------------------------------------
  // Status & Feedback
  // ---------------------------------------------------------------------------
  static String get alreadyToday => isEn ? 'Already on today' : '已经是今天';
  static String get returnedToToday => isEn ? 'Returned to today' : '已回到今天';

  static String goTodayFeedback({
    required bool alreadyToday,
    AppLocale? locale,
  }) {
    final isEnglish = (locale ?? I18n.current) == AppLocale.en;
    return alreadyToday
        ? (isEnglish ? 'Already on today' : '已经是今天')
        : (isEnglish ? 'Returned to today' : '已回到今天');
  }

  // ---------------------------------------------------------------------------
  // Weekday initials & Navigation
  // ---------------------------------------------------------------------------
  static List<String> get weekdayInitials => isEn
      ? const ['M', 'T', 'W', 'T', 'F', 'S', 'S']
      : const ['一', '二', '三', '四', '五', '六', '日'];

  static String monthHeader(int month, [AppLocale? locale]) {
    final isEnglish = (locale ?? I18n.current) == AppLocale.en;
    return isEnglish ? _enMonth(month) : '$month月';
  }

  static String yearHeader(int year, [AppLocale? locale]) {
    final isEnglish = (locale ?? I18n.current) == AppLocale.en;
    return isEnglish ? '$year' : '$year年';
  }

  static String fullDateTitle(
    DateTime date, [
    AppLocale? locale,
    String? pattern,
  ]) {
    final isEnglish = (locale ?? I18n.current) == AppLocale.en;
    if (!isEnglish) {
      const weekNames = ['一', '二', '三', '四', '五', '六', '日'];
      return '${I18nDateFormat.date(date, pattern: pattern, locale: locale)}星期${weekNames[date.weekday - 1]}';
    }
    return '${I18nDateFormat.date(date, pattern: pattern, locale: locale)} · ${_enWeekday(date.weekday)}';
  }

  // ---------------------------------------------------------------------------
  // Skipped Civil Day (e.g. Pacific/Apia 2011-12-30)
  // ---------------------------------------------------------------------------
  static String skippedCivilDayTitle(
    int year,
    int month,
    int day, [
    AppLocale? locale,
    String? pattern,
  ]) {
    final isEnglish = (locale ?? I18n.current) == AppLocale.en;
    // UTC contains the original civil components even for a skipped local day.
    return I18nDateFormat.date(
      DateTime.utc(year, month, day),
      pattern: pattern,
      locale: isEnglish ? AppLocale.en : AppLocale.zh,
    );
  }

  static String skippedCivilDayNotice([AppLocale? locale]) {
    final isEnglish = (locale ?? I18n.current) == AppLocale.en;
    return isEnglish ? 'Civil day skipped in local timezone' : '本地时区未包含此公历日';
  }

  static String skippedCivilDayExplanation([AppLocale? locale]) {
    final isEnglish = (locale ?? I18n.current) == AppLocale.en;
    return isEnglish
        ? 'This date is unrepresented in the device\'s local timezone. Almanac data is unavailable.'
        : '该公历日在本地时区中不存在（当地历法跳过该日），农历与黄历数据不可用。';
  }

  static String skippedDateFullTitle(
    DateTime utcCivil, [
    AppLocale? locale,
    String? pattern,
  ]) {
    final isEnglish = (locale ?? I18n.current) == AppLocale.en;
    if (isEnglish) {
      return '${I18nDateFormat.date(utcCivil, pattern: pattern, locale: AppLocale.en)} · Unavailable';
    }
    return '${I18nDateFormat.date(utcCivil, pattern: pattern, locale: AppLocale.zh)} · 暂不可用';
  }

  // ---------------------------------------------------------------------------
  // Month Highlights
  // ---------------------------------------------------------------------------
  static String get monthHighlightsTitle =>
      isEn ? 'Monthly Highlights' : '本月重点日期';

  static String monthBadge(int month) => isEn ? _enMonth(month) : '$month 月';

  static String get monthHighlightsEmpty =>
      isEn ? 'No highlights this month' : '本月暂无重点日期';

  static String moreHighlights(int count) =>
      isEn ? '$count more highlights' : '还有 $count 个重点日期';

  // ---------------------------------------------------------------------------
  // Badges & Labels
  // ---------------------------------------------------------------------------
  static String get holidayBadge => isEn ? 'Public Holiday' : '法定假日';
  static String get makeupWorkdayBadge => isEn ? 'Makeup Workday' : '调休上班';
  static String get holidayTag => isEn ? 'Off' : '休';
  static String get makeupWorkdayTag => isEn ? 'Work' : '班';

  static String termBadge(String term) => isEn
      ? 'Term ${AlmanacLocaleFormat.formatSolarTerm(term) ?? term}'
      : '节气 $term';

  static String solarFestivalBadge(String festival) => isEn
      ? 'Solar ${AlmanacLocaleFormat.formatFestival(festival) ?? festival}'
      : '公历 $festival';

  static String lunarFestivalBadge(String festival) => isEn
      ? 'Lunar ${AlmanacLocaleFormat.formatFestival(festival) ?? festival}'
      : '农历 $festival';

  static String termHighlight(String term) => isEn
      ? 'Term · ${AlmanacLocaleFormat.formatSolarTerm(term) ?? term}'
      : '节气 · $term';

  static String solarFestivalHighlight(String festival) => isEn
      ? 'Festival · ${AlmanacLocaleFormat.formatFestival(festival) ?? festival}'
      : '节日 · $festival';

  static String lunarFestivalHighlight(String festival) => isEn
      ? 'Lunar · ${AlmanacLocaleFormat.formatFestival(festival) ?? festival}'
      : '农历 · $festival';

  static String countdownHighlight(String title) =>
      isEn ? 'Countdown · $title' : '倒数日 · $title';

  static String birthdayHighlight(String title) =>
      isEn ? 'Birthday · $title' : '生日 · $title';

  static String memorialHighlight(String title) =>
      isEn ? 'Anniversary · $title' : '纪念日 · $title';

  // ---------------------------------------------------------------------------
  // Yiji & Summary
  // ---------------------------------------------------------------------------
  static String get auspiciousLabel => isEn ? 'Fit' : '宜';
  static String get inauspiciousLabel => isEn ? 'Avoid' : '忌';

  // ---------------------------------------------------------------------------
  // Unavailable & Fallbacks
  // ---------------------------------------------------------------------------
  static String get unavailable => isEn ? 'Unavailable' : '暂不可用';
  static String get almanacUnavailable =>
      isEn ? 'Almanac data unavailable' : '暂无黄历数据';
  static String get lunarUnavailable =>
      isEn ? 'Lunar date unavailable' : '农历暂不可用';
  static String get hourFortuneUnavailable =>
      isEn ? 'Hour fortunes unavailable' : '时辰吉凶暂不可用';

  // ---------------------------------------------------------------------------
  // Hour Fortunes Dialog
  // ---------------------------------------------------------------------------
  static String hourFortuneDialogTitle(
    String branch,
    bool isAuspicious, {
    AppLocale? locale,
  }) {
    final isEnglish = (locale ?? I18n.current) == AppLocale.en;
    if (!isEnglish) {
      return '$branch时 · ${isAuspicious ? '吉' : '凶'}';
    }
    return '$branch Hour · ${isAuspicious ? 'Auspicious' : 'Inauspicious'}';
  }

  static String hourDetailTime({AppLocale? locale}) {
    final isEnglish = (locale ?? I18n.current) == AppLocale.en;
    return isEnglish ? 'Time' : '时间';
  }

  static String hourDetailGanzhi({AppLocale? locale}) {
    final isEnglish = (locale ?? I18n.current) == AppLocale.en;
    return isEnglish ? 'Stem-Branch' : '干支';
  }

  static String hourDetailDeity({AppLocale? locale}) {
    final isEnglish = (locale ?? I18n.current) == AppLocale.en;
    return isEnglish ? 'Deity' : '神煞';
  }

  static String dialogConfirm({AppLocale? locale}) {
    final isEnglish = (locale ?? I18n.current) == AppLocale.en;
    return isEnglish ? 'Got it' : '知道了';
  }

  // ---------------------------------------------------------------------------
  // Semantics helpers
  // ---------------------------------------------------------------------------
  static String dayCellSemanticLabel(
    DateTime? day,
    int dayNumber,
    String label, {
    required bool isSelected,
    required bool isToday,
    String? pattern,
  }) {
    if (day == null) {
      return isEn ? 'Day $dayNumber, unavailable' : '$dayNumber日 暂不可用';
    }
    if (isEn) {
      final parts = <String>[
        I18nDateFormat.date(day, pattern: pattern),
        if (isToday) 'Today',
        if (isSelected) 'Selected',
        if (label.isNotEmpty) label,
      ];
      return parts.join(', ');
    }
    return '${I18nDateFormat.date(day, pattern: pattern)} $label';
  }

  // ---------------------------------------------------------------------------
  // P0/P1/P2 Extended Almanac & Tools Copy
  // ---------------------------------------------------------------------------
  static String get almanacToolsTitle => isEn ? 'Almanac Tools' : '万年历工具箱';
  static String get openAlmanacLabel => isEn ? 'Almanac' : '万年历';
  static String get fullAlmanacAndAuspiciousAction =>
      isEn ? 'Full Almanac & Dates' : '完整黄历与择吉';
  static String get tabClassicalAlmanac => isEn ? 'Daily Almanac' : '老黄历详版';
  static String get tabAuspiciousPicker => isEn ? 'Auspicious Days' : '择吉日';
  static String get tabHolidaySchedule => isEn ? 'Holidays' : '放假安排';
  static String get tabDateTools => isEn ? 'Date Tools' : '日期工具';
  static String get tabSolarTermsBazi => isEn ? 'Terms & BaZi' : '节气与八字';

  // Classical Almanac detail labels (localized ZH & EN)
  static String get fetalGodLabel => isEn ? 'Fetal God' : '胎神';
  static String get pengZuLabel => isEn ? 'PengZu' : '彭祖';
  static String get fiveElementsLabel => isEn ? 'Elements' : '五行';
  static String get mansionLabel => isEn ? 'Mansion' : '星宿';
  static String get clashLabel => isEn ? 'Clash' : '冲煞';
  static String get shichenTitle => isEn ? 'Twelve Hours' : '十二时辰吉凶';

  // P1 神煞方位
  static String get deitiesAndDirectionsTitle =>
      isEn ? 'Deities & Directions' : '神煞与吉神方位';
  static String get jiShenLabel => isEn ? 'Auspicious Spirits' : '吉神宜趋';
  static String get xiongShaLabel => isEn ? 'Inauspicious Spirits' : '凶神宜忌';
  static String get caiShenLabel => isEn ? 'Wealth God' : '财神';
  static String get xiShenLabel => isEn ? 'Joy God' : '喜神';
  static String get fuShenLabel => isEn ? 'Fortune God' : '福神';
  static String get yangGuiLabel => isEn ? 'Yang Noble' : '阳贵神';
  static String get yinGuiLabel => isEn ? 'Yin Noble' : '阴贵神';
  static String get tianShenLabel => isEn ? 'Day Officer' : '值神';
  static String get zhiXingLabel => isEn ? '12 Duty Officer' : '建除十二神';
  static String get huangDaoLabel => isEn ? 'Huangdao Day' : '黄道吉日';
  static String get heiDaoLabel => isEn ? 'Heidao Day' : '黑道日';

  // P1 物候民俗 & 节气倒计时 & 周数星座
  static String get phenologyAndSeasonTitle =>
      isEn ? 'Phenology & Season' : '物候民俗与节气';
  static String get shuJiuLabel => isEn ? 'Winter Nines' : '数九';
  static String get sanFuLabel => isEn ? 'Dog Days (Sanfu)' : '三伏';
  static String get wuHouLabel => isEn ? '72 Pentads' : '七十二候';
  static String get houLabel => isEn ? 'Solar Pentad' : '节气三候';
  static String get yueXiangLabel => isEn ? 'Moon Phase' : '月相';
  static String get xingZuoLabel => isEn ? 'Zodiac Sign' : '星座';
  static String get nextSolarTermLabel => isEn ? 'Next Solar Term' : '下个节气';

  static String isoWeekBadge(int week, [AppLocale? locale]) {
    final isEnglish = (locale ?? I18n.current) == AppLocale.en;
    return isEnglish ? 'W${week.toString().padLeft(2, '0')}' : '第$week周';
  }

  static String dayOfYearBadge(int day, [AppLocale? locale]) {
    final isEnglish = (locale ?? I18n.current) == AppLocale.en;
    return isEnglish ? 'Day $day of year' : '第$day天';
  }

  static String solarTermCountdownText(
    NextSolarTermInfo info, [
    AppLocale? locale,
  ]) {
    final current = locale ?? I18n.current;
    final termName = AlmanacLocaleFormat.formatSolarTerm(info.name, current) ?? info.name;
    if (current == AppLocale.en) {
      return '$termName in ${info.daysRemaining}d ${info.hoursRemaining}h ${info.minutesRemaining}m';
    }
    return '距$termName还有 ${info.daysRemaining}天${info.hoursRemaining}小时${info.minutesRemaining}分';
  }

  // Hour dialog extra labels
  static String get hourYiLabel => isEn ? 'Suitable' : '时辰宜';
  static String get hourJiLabel => isEn ? 'Avoid' : '时辰忌';
  static String get hourPositionsLabel => isEn ? 'God Positions' : '财喜福方位';
  static String get hourChongShaLabel => isEn ? 'Clash & Sha' : '冲煞';
  static String get hourNaYinLabel => isEn ? 'NaYin' : '纳音';

  // Expand / collapse & plain dictionary
  static String get expandAllTerms => isEn ? 'Show all' : '展开全部';
  static String get collapseTerms => isEn ? 'Collapse' : '收起';
  static String get tapTermForExplanationHint =>
      isEn ? 'Tap any term for plain explanation' : '点击任意宜忌词条查看白话释义';
  static String get plainExplanationTitle => isEn ? 'Plain Meaning' : '白话释义';

  // Holiday Schedule & Countdown
  static String nextHolidayHeroTitle(
    HolidayScheduleItem item,
    DateTime from, [
    AppLocale? locale,
  ]) {
    final current = locale ?? I18n.current;
    final name = item.localizedName(current);
    final days = item.daysUntil(from);
    if (days <= 0) {
      return current == AppLocale.en
          ? '$name holiday is ongoing!'
          : '正在放假中 · $name';
    }
    return current == AppLocale.en
        ? '$days days until $name'
        : '距离下一个法定节假日（$name）还有 $days 天';
  }

  static String holidayDaysBadge(int days, [AppLocale? locale]) {
    final isEnglish = (locale ?? I18n.current) == AppLocale.en;
    return isEnglish ? '$days days off' : '连休 $days 天';
  }

  static String get makeupWorkdaysLabel => isEn ? 'Makeup Workdays' : '调休补班';
  static String get noMakeupWorkdaysLabel => isEn ? 'No makeup workday' : '无需调休';
  static String get bridgeLeaveTipLabel => isEn ? 'Leave Tip' : '拼假建议';

  // Auspicious Day Finder
  static String get selectActivityLabel => isEn ? 'Choose Activity' : '选择事项';
  static String get searchActivityHint =>
      isEn ? 'Search activity (e.g. wedding, moving)' : '搜索事项（如结婚、搬家、开业）';
  static String get weekendsOrHolidaysOnlyLabel =>
      isEn ? 'Weekends & holidays only' : '仅看周末 / 节假日';
  static String get avoidZodiacLabel => isEn ? 'Avoid Clash Zodiac' : '避开冲生肖';
  static String get noZodiacFilterLabel => isEn ? 'No limit' : '不限生肖';
  static String get weekendTag => isEn ? 'Weekend' : '周末';

  static String rangeDaysOption(int days, [AppLocale? locale]) {
    final isEnglish = (locale ?? I18n.current) == AppLocale.en;
    return isEnglish ? 'Next $days days' : '未来 $days 天';
  }

  static String auspiciousMatchesSummary(int count, [AppLocale? locale]) {
    final isEnglish = (locale ?? I18n.current) == AppLocale.en;
    return isEnglish ? '$count auspicious days found' : '共找到 $count 个黄道/宜行吉日';
  }

  static String get noAuspiciousDaysFound => isEn
      ? 'No matching days in this range. Try expanding the date window.'
      : '当前条件范围内暂无匹配日期，可尝试扩大查询天数或关闭周末限制。';

  // Date Interval & Offset & Converter
  static String get intervalCalcTitle => isEn ? 'Date Interval' : '日期间隔计算';
  static String get offsetCalcTitle => isEn ? 'Date Offset' : '日期加减推算';
  static String get solarLunarConverterTitle =>
      isEn ? 'Solar ↔ Lunar Converter' : '公农历互转';
  static String get startDateLabel => isEn ? 'Start Date' : '开始日期';
  static String get endDateLabel => isEn ? 'End Date' : '结束日期';
  static String get includeEndDateLabel => isEn ? 'Include end date' : '包含结束日';
  static String get calendarDaysLabel => isEn ? 'Calendar Days' : '自然日';
  static String get workdaysLabel => isEn ? 'Workdays' : '法定工作日';
  static String get weekendDaysLabel => isEn ? 'Weekends' : '周末';
  static String get holidayDaysLabel => isEn ? 'Public Holidays' : '法定假日';
  static String get makeupDaysLabel => isEn ? 'Makeup Days' : '调休补班';
  static String get restDaysLabel => isEn ? 'Rest Days' : '休息日';
  static String get baseDateLabel => isEn ? 'Base Date' : '基准日期';
  static String get deltaDaysLabel => isEn ? 'Offset Days' : '偏移天数（可正负）';
  static String get workdaysOnlyLabel => isEn ? 'Workdays only' : '仅按工作日推算';
  static String get targetDateLabel => isEn ? 'Target Date' : '推算结果';
  static String get solarToLunarTab => isEn ? 'Solar → Lunar' : '公历转农历';
  static String get lunarToSolarTab => isEn ? 'Lunar → Solar' : '农历转公历';
  static String get isLeapMonthLabel => isEn ? 'Leap Month' : '闰月';
  static String get yearHasNoLeapMonth =>
      isEn ? 'No leap month in this lunar year' : '该农历年无闰月';

  // Solar Terms & BaZi
  static String get yearSolarTermsTitle => isEn ? '24 Solar Terms' : '全年 24 节气时刻表';
  static String get baziTitle => isEn ? 'BaZi (Four Pillars)' : '生辰八字简排';
  static String get birthDateTimeLabel => isEn ? 'Birth Date & Time' : '出生日期与时辰';
  static String get yearPillarLabel => isEn ? 'Year' : '年柱';
  static String get monthPillarLabel => isEn ? 'Month' : '月柱';
  static String get dayPillarLabel => isEn ? 'Day' : '日柱';
  static String get timePillarLabel => isEn ? 'Hour' : '时柱';
  static String get wuXingSummaryLabel => isEn ? 'Five Elements' : '五行分布';
  static String get dayMasterLabel => isEn ? 'Day Master' : '日主';

  static String _enMonth(int month) {
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[(month - 1).clamp(0, 11)];
  }

  static String _enWeekday(int weekday) {
    const en = <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return en[(weekday - 1).clamp(0, 6)];
  }
}
