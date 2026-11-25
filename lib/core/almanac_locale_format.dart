/// Locale-aware formatting for lunar calendar, solar terms, festivals,
/// classical almanac fields, and Yi/Ji activities.
library;

import 'i18n.dart';
import 'lunar_calendar.dart';

class AlmanacLocaleFormat {
  AlmanacLocaleFormat._();

  static bool get isEn => I18n.current == AppLocale.en;
  static bool get isZh => I18n.current == AppLocale.zh;

  static const List<String> _stemsEn = <String>[
    'Jia',
    'Yi',
    'Bing',
    'Ding',
    'Wu',
    'Ji',
    'Geng',
    'Xin',
    'Ren',
    'Gui',
  ];

  static const List<String> _branchesEn = <String>[
    'Zi',
    'Chou',
    'Yin',
    'Mao',
    'Chen',
    'Si',
    'Wu',
    'Wei',
    'Shen',
    'You',
    'Xu',
    'Hai',
  ];

  static const Map<String, String> _stemsMap = <String, String>{
    '甲': 'Jia',
    '乙': 'Yi',
    '丙': 'Bing',
    '丁': 'Ding',
    '戊': 'Wu',
    '己': 'Ji',
    '庚': 'Geng',
    '辛': 'Xin',
    '壬': 'Ren',
    '癸': 'Gui',
  };

  static const Map<String, String> _branchesMap = <String, String>{
    '子': 'Zi',
    '丑': 'Chou',
    '寅': 'Yin',
    '卯': 'Mao',
    '辰': 'Chen',
    '巳': 'Si',
    '午': 'Wu',
    '未': 'Wei',
    '申': 'Shen',
    '酉': 'You',
    '戌': 'Xu',
    '亥': 'Hai',
  };

  /// Formats [LunarDate] into localized text.
  /// zh: "八月廿五" / "闰四月初二"
  /// en: "Month 8, Day 25" / "Leap Month 4, Day 2"
  static String formatLunarDate(LunarDate lunar, [AppLocale? locale]) {
    final current = locale ?? I18n.current;
    if (current == AppLocale.zh) {
      return lunar.chineseText;
    }
    final prefix = lunar.isLeapMonth ? 'Leap Month' : 'Month';
    return '$prefix ${lunar.month}, Day ${lunar.day}';
  }

  /// The year used by lunar pickers, including the sexagenary cycle name.
  /// [solarYear] preserves the solar picker's existing Chinese year context.
  static String formatLunarYear(int year, {int? solarYear, AppLocale? locale}) {
    if ((locale ?? I18n.current) == AppLocale.zh) {
      return '${LunarCalendar.ganzhiOf(year)}年（${solarYear ?? year}）';
    }
    final stemIndex = ((year - 4) % 10 + 10) % 10;
    final branchIndex = ((year - 4) % 12 + 12) % 12;
    return '$year (${_stemsEn[stemIndex]}-${_branchesEn[branchIndex]})';
  }

  /// A full date for corresponding-date labels and anniversary editors.
  static String formatFullLunarDate(
    LunarDate lunar, {
    bool includeGanzhi = false,
    AppLocale? locale,
  }) {
    final current = locale ?? I18n.current;
    final year = includeGanzhi
        ? formatLunarYear(lunar.year, locale: current)
        : current == AppLocale.zh
        ? '${lunar.year}年'
        : '${lunar.year}';
    final separator = current == AppLocale.zh ? '' : ', ';
    return '$year$separator${formatLunarDate(lunar, current)}';
  }

  static String formatLunarDay(LunarDate lunar, [AppLocale? locale]) =>
      (locale ?? I18n.current) == AppLocale.zh
      ? lunar.dayChineseText
      : 'Day ${lunar.day}';

  /// Formats solar term (节气) to localized text.
  static String? formatSolarTerm(String? term, [AppLocale? locale]) {
    if (term == null || term.isEmpty) return null;
    final current = locale ?? I18n.current;
    if (current == AppLocale.zh) return term;
    return _solarTerms[term] ?? term;
  }

  /// Formats solar or lunar festival (节日) to localized text.
  static String? formatFestival(String? festival, [AppLocale? locale]) {
    if (festival == null || festival.isEmpty) return null;
    final current = locale ?? I18n.current;
    if (current == AppLocale.zh) return festival;
    return _festivals[festival] ?? festival;
  }

  /// Formats a single Yi/Ji activity term.
  static String formatActivityTerm(String term, [AppLocale? locale]) {
    final trimmed = term.trim();
    if (trimmed.isEmpty) return '';
    final current = locale ?? I18n.current;
    if (current == AppLocale.zh) return trimmed;
    return _yiJiTerms[trimmed] ?? trimmed;
  }

  /// Formats auspicious (宜) space-separated activities.
  static String formatAuspicious(String suitable, [AppLocale? locale]) {
    final current = locale ?? I18n.current;
    if (current == AppLocale.zh) return suitable;
    return _translateAlmanacString(suitable);
  }

  /// Formats inauspicious (忌) space-separated activities.
  static String formatInauspicious(String avoid, [AppLocale? locale]) {
    final current = locale ?? I18n.current;
    if (current == AppLocale.zh) return avoid;
    return _translateAlmanacString(avoid);
  }

  /// Formats a concise activity preview for cards and tiles.
  /// Preserves Chinese original format when in Chinese (up to [maxTerms] terms
  /// joined by spaces, appended with ' …' if truncated).
  /// In English, terms are translated and joined with ', '. Unknown cultural
  /// terms are preserved as-is.
  static String formatActivitiesPreview(
    String raw, {
    int maxTerms = 4,
    AppLocale? locale,
  }) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';

    final current = locale ?? I18n.current;
    if (current == AppLocale.zh) {
      final terms = trimmed
          .split(RegExp(r'\s+'))
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList(growable: false);
      if (terms.length <= maxTerms) return terms.join(' ');
      return '${terms.take(maxTerms).join(' ')}\u00A0…';
    }

    if (trimmed == '诸事不宜') return 'Unfavorable for all';
    if (trimmed == '无') return 'None';
    if (trimmed == '馀事勿取') return 'Avoid other matters';

    final terms = trimmed
        .split(RegExp(r'\s+'))
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList(growable: false);
    if (terms.isEmpty) return '';

    final translated = terms.map((t) => _yiJiTerms[t] ?? t).toList();
    if (translated.length <= maxTerms) return translated.join(', ');
    return '${translated.take(maxTerms).join(', ')}\u00A0…';
  }

  /// Checks if a cultural activity term is in our curated dictionary.
  static bool isKnownYiJi(String term) => _yiJiTerms.containsKey(term.trim());

  /// Formats a zodiac animal (e.g. `马` -> `Horse`).
  static String formatZodiac(String zodiac, [AppLocale? locale]) {
    final trimmed = zodiac.trim();
    if ((locale ?? I18n.current) == AppLocale.zh) return trimmed;
    return _zodiacs[trimmed] ?? trimmed;
  }

  /// Formats constellation (e.g. `双子` -> `双子座` / `Gemini`).
  static String formatXingZuo(String xingZuo, [AppLocale? locale]) {
    final trimmed = xingZuo.trim().replaceAll('座', '');
    if (trimmed.isEmpty) return '';
    if ((locale ?? I18n.current) == AppLocale.zh) {
      return '$trimmed座';
    }
    return _xingZuoEn[trimmed] ?? trimmed;
  }

  /// Romanizes a 2-character GanZhi pillar (e.g. `戊申` -> `Wu-Shen`).
  static String formatGanZhi(String ganZhi, [AppLocale? locale]) {
    final trimmed = ganZhi.trim();
    if ((locale ?? I18n.current) == AppLocale.zh) return trimmed;
    if (trimmed.length >= 2) {
      final stem = _stemsMap[trimmed.substring(0, 1)];
      final branch = _branchesMap[trimmed.substring(1, 2)];
      if (stem != null && branch != null) {
        return '$stem-$branch';
      }
    }
    return trimmed;
  }

  /// Formats full Ganzhi line (year/month/day) cleanly in ZH/EN.
  static String formatGanzhiLine(
    LunarAlmanacDetail detail, [
    AppLocale? locale,
  ]) {
    if ((locale ?? I18n.current) == AppLocale.zh) {
      return detail.ganzhiLine;
    }
    final match = RegExp(
      r'^(.{2})(.)年(.{2})月(.{2})日$',
    ).firstMatch(detail.ganzhiLine);
    if (match != null) {
      final yGz = formatGanZhi(match.group(1)!, AppLocale.en);
      final zodiac = formatZodiac(match.group(2)!, AppLocale.en);
      final mGz = formatGanZhi(match.group(3)!, AppLocale.en);
      final dGz = formatGanZhi(match.group(4)!, AppLocale.en);
      return '$yGz ($zodiac) Yr · $mGz Mo · $dGz Day';
    }
    return '${formatGanZhi(detail.dayGanzhi, AppLocale.en)} Day';
  }

  /// Formats 12 Heavenly Officers (值神: 青龙..勾陈).
  static String formatTianShen(String tianShen, [AppLocale? locale]) {
    final trimmed = tianShen.trim();
    if ((locale ?? I18n.current) == AppLocale.zh) return trimmed;
    return _tianShenEn[trimmed] ?? trimmed;
  }

  /// Formats 黄道 / 黑道.
  static String formatTianShenType(String type, [AppLocale? locale]) {
    final trimmed = type.trim();
    if ((locale ?? I18n.current) == AppLocale.zh) return trimmed;
    return switch (trimmed) {
      '黄道' => 'Huangdao',
      '黑道' => 'Heidao',
      _ => trimmed,
    };
  }

  /// Formats 吉 / 凶.
  static String formatTianShenLuck(String luck, [AppLocale? locale]) {
    final trimmed = luck.trim();
    if ((locale ?? I18n.current) == AppLocale.zh) return trimmed;
    return switch (trimmed) {
      '吉' => 'Auspicious',
      '凶' => 'Inauspicious',
      _ => trimmed,
    };
  }

  /// Formats 建除十二神 (建..闭).
  static String formatZhiXing(String zhiXing, [AppLocale? locale]) {
    final trimmed = zhiXing.trim();
    if ((locale ?? I18n.current) == AppLocale.zh) return trimmed;
    return _zhiXingEn[trimmed] ?? trimmed;
  }

  /// Formats compass direction (`正北` -> `North`, `东北` -> `Northeast`, etc.).
  static String formatDirection(String direction, [AppLocale? locale]) {
    final trimmed = direction.trim();
    if ((locale ?? I18n.current) == AppLocale.zh) return trimmed;
    return _directionEn[trimmed] ?? trimmed;
  }

  /// Formats moon phase (月相).
  static String formatYueXiang(String phase, [AppLocale? locale]) {
    final trimmed = phase.trim();
    if ((locale ?? I18n.current) == AppLocale.zh) return trimmed;
    return _yueXiangEn[trimmed] ?? trimmed;
  }

  /// Formats 五行 string (single element like `金` or paired `火火`).
  static String formatWuXing(String wuXing, [AppLocale? locale]) {
    final trimmed = wuXing.trim();
    if ((locale ?? I18n.current) == AppLocale.zh) return trimmed;
    final parts = <String>[];
    for (final rune in trimmed.runes) {
      final ch = String.fromCharCode(rune);
      parts.add(_wuXingEn[ch] ?? ch);
    }
    return parts.join(' / ');
  }

  /// Formats 60 JiaZi NaYin (e.g. `大驿土` -> `Highway Earth`).
  static String formatNaYin(String naYin, [AppLocale? locale]) {
    final trimmed = naYin.trim();
    if ((locale ?? I18n.current) == AppLocale.zh) return trimmed;
    return _naYinEn[trimmed] ?? trimmed;
  }

  /// Formats Five Elements + ZhiXing officer (`大驿土平执位`).
  static String formatFiveElements(
    String fiveElements, {
    String? dayNaYin,
    String? zhiXing,
    AppLocale? locale,
  }) {
    if ((locale ?? I18n.current) == AppLocale.zh) return fiveElements;
    final ny = (dayNaYin ?? '').trim();
    final zx = (zhiXing ?? '').trim();
    if (ny.isNotEmpty && zx.isNotEmpty) {
      return '${formatNaYin(ny, AppLocale.en)} · ${formatZhiXing(zx, AppLocale.en)} Officer';
    }
    final cleaned = fiveElements.replaceAll('执位', '').trim();
    for (final key in _naYinEn.keys) {
      if (cleaned.startsWith(key)) {
        final officer = cleaned.substring(key.length).trim();
        final officerEn = officer.isEmpty
            ? ''
            : ' · ${formatZhiXing(officer, AppLocale.en)} Officer';
        return '${_naYinEn[key]!}$officerEn';
      }
    }
    return fiveElements;
  }

  /// Formats daily clash & evil direction (e.g. `猴日冲虎（壬寅）煞南`).
  static String formatClash(LunarAlmanacDetail detail, [AppLocale? locale]) {
    if ((locale ?? I18n.current) == AppLocale.zh) return detail.clash;
    final match = RegExp(
      r'^(.)日冲(.)（(.{2})）煞(.)$',
    ).firstMatch(detail.clash);
    if (match != null) {
      final dayZ = formatZodiac(match.group(1)!, AppLocale.en);
      final clashZ = formatZodiac(match.group(2)!, AppLocale.en);
      final gz = formatGanZhi(match.group(3)!, AppLocale.en);
      final dir = formatDirection(match.group(4)!, AppLocale.en);
      return '$dayZ Day clashes $clashZ ($gz) · Sha $dir';
    }
    return detail.clash;
  }

  /// Formats hourly clash & evil direction (e.g. `冲虎（壬寅）煞南`).
  static String formatHourChongSha(String chongSha, [AppLocale? locale]) {
    if ((locale ?? I18n.current) == AppLocale.zh) return chongSha;
    final match = RegExp(r'^冲(.)（(.{2})）煞(.)$').firstMatch(chongSha.trim());
    if (match != null) {
      final clashZ = formatZodiac(match.group(1)!, AppLocale.en);
      final gz = formatGanZhi(match.group(2)!, AppLocale.en);
      final dir = formatDirection(match.group(3)!, AppLocale.en);
      return 'Clashes $clashZ ($gz) · Sha $dir';
    }
    return chongSha;
  }

  /// Formats 28 Mansions (`东方箕水豹-吉`).
  static String formatMansion(String mansion, [AppLocale? locale]) {
    if ((locale ?? I18n.current) == AppLocale.zh) return mansion;
    final match = RegExp(
      r'^(东方|西方|南方|北方)(.+)-(吉|凶)$',
    ).firstMatch(mansion.trim());
    if (match != null) {
      final dir = formatDirection(match.group(1)!, AppLocale.en);
      final starRaw = match.group(2)!;
      final starName = starRaw.isNotEmpty
          ? _xiuEn[starRaw.substring(0, 1)] ?? starRaw
          : starRaw;
      final luck = formatTianShenLuck(match.group(3)!, AppLocale.en);
      return '$dir · $starName ($luck)';
    }
    return mansion;
  }

  /// Formats Fetal God position (`房床炉房内中`).
  static String formatFetalGod(String fetalGod, [AppLocale? locale]) {
    if ((locale ?? I18n.current) == AppLocale.zh) return fetalGod;
    final raw = fetalGod.trim();
    for (final loc in _fetalLocationsEn.entries) {
      if (raw.endsWith(loc.key)) {
        final obj = raw.substring(0, raw.length - loc.key.length);
        final objEn = _fetalObjectsEn[obj] ?? obj;
        return '$objEn · ${loc.value}';
      }
    }
    return raw;
  }

  /// Formats PengZu taboos (`戊不受田，田主不祥；申不安床，鬼祟入房`).
  static String formatPengZu(String pengZu, [AppLocale? locale]) {
    if ((locale ?? I18n.current) == AppLocale.zh) return pengZu;
    final parts = pengZu.split('；');
    if (parts.length == 2) {
      final ganPart = parts[0].trim();
      final zhiPart = parts[1].trim();
      final ganKey = ganPart.isNotEmpty ? ganPart.substring(0, 1) : '';
      final zhiKey = zhiPart.isNotEmpty ? zhiPart.substring(0, 1) : '';
      final gEn = _pengZuGanEn[ganKey];
      final zEn = _pengZuZhiEn[zhiKey];
      if (gEn != null && zEn != null) {
        return '$gEn; $zEn';
      }
    }
    return pengZu;
  }

  /// Formats 数九 (`一九第3天` -> `1st Nine, Day 3`).
  static String? formatShuJiu(String? shuJiu, [AppLocale? locale]) {
    if (shuJiu == null || shuJiu.isEmpty) return null;
    if ((locale ?? I18n.current) == AppLocale.zh) return shuJiu;
    final match = RegExp(r'^(.)九第(\d+)天$').firstMatch(shuJiu.trim());
    if (match != null) {
      final idx = _cnNumMap[match.group(1)!] ?? 1;
      final ord = _ordinal(idx);
      return '$ord Nine, Day ${match.group(2)}';
    }
    return shuJiu;
  }

  /// Formats 三伏 (`初伏第1天` -> `First Fu, Day 1`).
  static String? formatSanFu(String? sanFu, [AppLocale? locale]) {
    if (sanFu == null || sanFu.isEmpty) return null;
    if ((locale ?? I18n.current) == AppLocale.zh) return sanFu;
    final match = RegExp(r'^(初伏|中伏|末伏)第(\d+)天$').firstMatch(sanFu.trim());
    if (match != null) {
      final phase = switch (match.group(1)) {
        '初伏' => 'First Fu',
        '中伏' => 'Middle Fu',
        '末伏' => 'Final Fu',
        _ => match.group(1)!,
      };
      return '$phase, Day ${match.group(2)}';
    }
    return sanFu;
  }

  /// Formats 节气三候 (`小满 三候` -> `Grain Buds · 3rd Pentad`).
  static String formatHou(String hou, [AppLocale? locale]) {
    final trimmed = hou.trim();
    if ((locale ?? I18n.current) == AppLocale.zh) return trimmed;
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length == 2) {
      final termEn = formatSolarTerm(parts[0], AppLocale.en) ?? parts[0];
      final pentadEn = switch (parts[1]) {
        '初候' => '1st Pentad',
        '二候' => '2nd Pentad',
        '三候' => '3rd Pentad',
        _ => parts[1],
      };
      return '$termEn · $pentadEn';
    }
    return trimmed;
  }

  /// Formats 72 物候 (`螳螂生` -> `Mantis Emerges`).
  static String formatWuHou(String wuHou, [AppLocale? locale]) {
    final trimmed = wuHou.trim();
    if ((locale ?? I18n.current) == AppLocale.zh) return trimmed;
    return _wuHouEn[trimmed] ?? trimmed;
  }

  /// Formats a single ShenSha (吉神/凶神) name.
  static String formatShenSha(String item, [AppLocale? locale]) {
    final trimmed = item.trim();
    if ((locale ?? I18n.current) == AppLocale.zh) return trimmed;
    return _shenShaEn[trimmed] ?? trimmed;
  }

  static List<String> formatShenShaList(
    List<String> items, [
    AppLocale? locale,
  ]) {
    return items
        .map((e) => formatShenSha(e, locale))
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }

  static String _translateAlmanacString(String raw) {
    final trimmed = raw.trim();
    if (trimmed == '诸事不宜') return 'Unfavorable for all';
    if (trimmed == '无') return 'None';
    if (trimmed == '馀事勿取') return 'Avoid other matters';

    final tokens = trimmed
        .split(RegExp(r'\s+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty);
    if (tokens.isEmpty) return '';
    return tokens.map((t) => _yiJiTerms[t] ?? t).join(', ');
  }

  static String _ordinal(int n) {
    return switch (n) {
      1 => '1st',
      2 => '2nd',
      3 => '3rd',
      _ => '${n}th',
    };
  }

  // ---------------------------------------------------------------------------
  // Dictionaries
  // ---------------------------------------------------------------------------

  static const Map<String, int> _cnNumMap = <String, int>{
    '一': 1,
    '二': 2,
    '三': 3,
    '四': 4,
    '五': 5,
    '六': 6,
    '七': 7,
    '八': 8,
    '九': 9,
  };

  static const Map<String, String> _zodiacs = <String, String>{
    '鼠': 'Rat',
    '牛': 'Ox',
    '虎': 'Tiger',
    '兔': 'Rabbit',
    '龙': 'Dragon',
    '蛇': 'Snake',
    '马': 'Horse',
    '羊': 'Goat',
    '猴': 'Monkey',
    '鸡': 'Rooster',
    '狗': 'Dog',
    '猪': 'Pig',
  };

  static const Map<String, String> _xingZuoEn = <String, String>{
    '白羊': 'Aries',
    '金牛': 'Taurus',
    '双子': 'Gemini',
    '巨蟹': 'Cancer',
    '狮子': 'Leo',
    '处女': 'Virgo',
    '天秤': 'Libra',
    '天蝎': 'Scorpio',
    '射手': 'Sagittarius',
    '摩羯': 'Capricorn',
    '水瓶': 'Aquarius',
    '双鱼': 'Pisces',
  };

  static const Map<String, String> _tianShenEn = <String, String>{
    '青龙': 'Azure Dragon',
    '明堂': 'Bright Hall',
    '天刑': 'Heavenly Punishment',
    '朱雀': 'Vermilion Bird',
    '金匮': 'Golden Coffer',
    '天德': 'Heavenly Virtue',
    '白虎': 'White Tiger',
    '玉堂': 'Jade Hall',
    '天牢': 'Heavenly Prison',
    '玄武': 'Black Tortoise',
    '司命': 'Life Governor',
    '勾陈': 'Grappling Hook',
  };

  static const Map<String, String> _zhiXingEn = <String, String>{
    '建': 'Establish',
    '除': 'Remove',
    '满': 'Full',
    '平': 'Balance',
    '定': 'Stable',
    '执': 'Hold',
    '破': 'Break',
    '危': 'Danger',
    '成': 'Success',
    '收': 'Harvest',
    '开': 'Open',
    '闭': 'Close',
  };

  static const Map<String, String> _directionEn = <String, String>{
    '正北': 'North',
    '北': 'North',
    '北方': 'North',
    '东北': 'Northeast',
    '正东': 'East',
    '东': 'East',
    '东方': 'East',
    '东南': 'Southeast',
    '正南': 'South',
    '南': 'South',
    '南方': 'South',
    '西南': 'Southwest',
    '正西': 'West',
    '西': 'West',
    '西方': 'West',
    '西北': 'Northwest',
    '中宫': 'Center',
  };

  static const Map<String, String> _wuXingEn = <String, String>{
    '金': 'Metal',
    '木': 'Wood',
    '水': 'Water',
    '火': 'Fire',
    '土': 'Earth',
  };

  static const Map<String, String> _yueXiangEn = <String, String>{
    '朔': 'New Moon',
    '既朔': 'Post-New Moon',
    '蛾眉新': 'Waxing Crescent',
    '蛾眉': 'Waxing Crescent',
    '夕': 'Evening Moon',
    '上弦': 'First Quarter',
    '九夜': 'Waxing Gibbous',
    '宵': 'Bright Night',
    '渐盈凸': 'Waxing Gibbous',
    '小望': 'Almost Full',
    '望': 'Full Moon',
    '既望': 'Waning Gibbous',
    '立待': 'Early Waning',
    '居待': 'Waning Gibbous',
    '寝待': 'Late Waning',
    '更待': 'Midnight Moon',
    '渐亏凸': 'Waning Gibbous',
    '下弦': 'Last Quarter',
    '有明': 'Morning Moon',
    '蛾眉残': 'Waning Crescent',
    '残': 'Waning Crescent',
    '晓': 'Dawn Crescent',
    '晦': 'Dark Moon',
  };

  static const Map<String, String> _naYinEn = <String, String>{
    '海中金': 'Sea Gold',
    '炉中火': 'Furnace Fire',
    '大林木': 'Forest Wood',
    '路旁土': 'Roadside Earth',
    '剑锋金': 'Sword Gold',
    '山头火': 'Hilltop Fire',
    '涧下水': 'Stream Water',
    '城头土': 'Rampart Earth',
    '白蜡金': 'Pewter Gold',
    '杨柳木': 'Willow Wood',
    '泉中水': 'Spring Water',
    '屋上土': 'Rooftop Earth',
    '霹雳火': 'Thunderbolt Fire',
    '松柏木': 'Pine Wood',
    '长流水': 'Long River Water',
    '沙中金': 'Sand Gold',
    '山下火': 'Foothill Fire',
    '平地木': 'Plain Wood',
    '壁上土': 'Wall Earth',
    '金箔金': 'Foil Gold',
    '覆灯火': 'Lamp Fire',
    '天河水': 'Milky Way Water',
    '大驿土': 'Highway Earth',
    '钗钏金': 'Hairpin Gold',
    '桑柘木': 'Mulberry Wood',
    '大溪水': 'Brook Water',
    '沙中土': 'Desert Earth',
    '天上火': 'Celestial Fire',
    '石榴木': 'Pomegranate Wood',
    '大海水': 'Ocean Water',
  };

  static const Map<String, String> _xiuEn = <String, String>{
    '角': 'Horn Mansion',
    '亢': 'Neck Mansion',
    '氐': 'Root Mansion',
    '房': 'Room Mansion',
    '心': 'Heart Mansion',
    '尾': 'Tail Mansion',
    '箕': 'Winnowing Basket',
    '斗': 'Dipper Mansion',
    '牛': 'Ox Mansion',
    '女': 'Girl Mansion',
    '虚': 'Emptiness Mansion',
    '危': 'Rooftop Mansion',
    '室': 'Encampment Mansion',
    '壁': 'Wall Mansion',
    '奎': 'Legs Mansion',
    '娄': 'Bond Mansion',
    '胃': 'Stomach Mansion',
    '昴': 'Hairy Head Mansion',
    '毕': 'Net Mansion',
    '觜': 'Turtle Beak',
    '参': 'Three Stars',
    '井': 'Well Mansion',
    '鬼': 'Ghost Mansion',
    '柳': 'Willow Mansion',
    '星': 'Star Mansion',
    '张': 'Extended Net',
    '翼': 'Wings Mansion',
    '轸': 'Chariot Mansion',
  };

  static const Map<String, String> _fetalObjectsEn = <String, String>{
    '占门碓': 'Gate & Millstone',
    '碓磨厕': 'Mill & Restroom',
    '厨灶炉': 'Kitchen & Stove',
    '仓库门': 'Storehouse & Gate',
    '房床栖': 'Bedroom & Perch',
    '占门床': 'Gate & Bed',
    '占碓磨': 'Millstone Area',
    '厨灶厕': 'Kitchen & Restroom',
    '仓库炉': 'Storehouse & Hearth',
    '房床门': 'Bed & Door',
    '占门栖': 'Gate & Perch',
    '碓磨床': 'Mill & Bed',
    '厨灶碓': 'Kitchen & Mill',
    '仓库厕': 'Storehouse & Restroom',
    '房床炉': 'Bed & Stove',
    '占大门': 'Main Gate',
    '碓磨栖': 'Mill & Perch',
    '厨灶床': 'Kitchen & Bed',
    '仓库碓': 'Storehouse & Mill',
    '房床厕': 'Bed & Restroom',
    '占门炉': 'Gate & Stove',
    '碓磨门': 'Mill & Gate',
    '厨灶栖': 'Kitchen & Perch',
    '仓库床': 'Storehouse & Bed',
    '房床碓': 'Bed & Mill',
    '占门厕': 'Gate & Restroom',
    '碓磨炉': 'Mill & Stove',
    '厨灶门': 'Kitchen & Gate',
    '仓库栖': 'Storehouse & Perch',
    '占房床': 'Bedroom & Bed',
  };

  static const Map<String, String> _fetalLocationsEn = <String, String>{
    '外东南': 'Outer Southeast',
    '外正南': 'Outer South',
    '外西南': 'Outer Southwest',
    '外正西': 'Outer West',
    '外西北': 'Outer Northwest',
    '外正北': 'Outer North',
    '外东北': 'Outer Northeast',
    '外正东': 'Outer East',
    '房内北': 'Inner North',
    '房内中': 'Inner Center',
    '房内南': 'Inner South',
    '房内西': 'Inner West',
    '房内东': 'Inner East',
  };

  static const Map<String, String> _pengZuGanEn = <String, String>{
    '甲': 'Jia: Avoid opening granary (loss)',
    '乙': 'Yi: Avoid planting (poor growth)',
    '丙': 'Bing: Avoid repairing stove (mishap)',
    '丁': 'Ding: Avoid shaving head (sores)',
    '戊': 'Wu: Avoid taking land (ill omen)',
    '己': 'Ji: Avoid breaking contracts',
    '庚': 'Geng: Avoid weaving looms',
    '辛': 'Xin: Avoid making sauces',
    '壬': 'Ren: Avoid dredging water',
    '癸': 'Gui: Avoid lawsuits',
  };

  static const Map<String, String> _pengZuZhiEn = <String, String>{
    '子': 'Zi: Avoid divination',
    '丑': 'Chou: Avoid crowning ceremonies',
    '寅': 'Yin: Avoid rituals',
    '卯': 'Mao: Avoid digging wells',
    '辰': 'Chen: Avoid weeping',
    '巳': 'Si: Avoid long travel',
    '午': 'Wu: Avoid roof thatching',
    '未': 'Wei: Avoid taking medicine',
    '申': 'Shen: Avoid setting bed',
    '酉': 'You: Avoid hosting banquets',
    '戌': 'Xu: Avoid eating dog meat',
    '亥': 'Hai: Avoid weddings',
  };

  static const Map<String, String> _wuHouEn = <String, String>{
    '蚯蚓结': 'Earthworms curl',
    '麋角解': 'Elks shed antlers',
    '水泉动': 'Springs stir',
    '雁北乡': 'Geese head north',
    '鹊始巢': 'Magpies build nests',
    '雉始雊': 'Pheasants call',
    '鸡始乳': 'Hens hatch chicks',
    '征鸟厉疾': 'Raptors fly fierce',
    '水泽腹坚': 'Streams freeze thick',
    '东风解冻': 'East wind thaws ice',
    '蛰虫始振': 'Hibernating insects stir',
    '鱼陟负冰': 'Fish rise under ice',
    '獭祭鱼': 'Otters offer fish',
    '候雁北': 'Wild geese fly north',
    '草木萌动': 'Plants sprout',
    '桃始华': 'Peach blossoms bloom',
    '仓庚鸣': 'Orioles sing',
    '鹰化为鸠': 'Hawks turn to doves',
    '玄鸟至': 'Swallows arrive',
    '雷乃发声': 'Thunder rumbles',
    '始电': 'Lightning flashes',
    '桐始华': 'Paulownia blossoms',
    '田鼠化为鴽': 'Field mice turn to quails',
    '虹始见': 'Rainbows appear',
    '萍始生': 'Duckweed grows',
    '鸣鸠拂其羽': 'Doves preen wings',
    '戴胜降于桑': 'Hoopoes perch on mulberries',
    '蝼蝈鸣': 'Frogs croak',
    '蚯蚓出': 'Earthworms emerge',
    '王瓜生': 'Gourds grow',
    '苦菜秀': 'Sowthistles flourish',
    '靡草死': 'Tender herbs wither',
    '麦秋至': 'Wheat ripens',
    '螳螂生': 'Mantises hatch',
    '鵙始鸣': 'Shrikes begin calling',
    '反舌无声': 'Mockingbirds fall silent',
    '鹿角解': 'Deer shed antlers',
    '蜩始鸣': 'Cicadas sing',
    '半夏生': 'Pinellia sprouts',
    '温风至': 'Warm winds arrive',
    '蟋蟀居壁': 'Crickets dwell by walls',
    '鹰始挚': 'Young hawks learn to hunt',
    '腐草为萤': 'Fireflies glow from grass',
    '土润溽暑': 'Soil dampens in heat',
    '大雨行时': 'Heavy summer rains fall',
    '凉风至': 'Cool breezes arrive',
    '白露降': 'White dew forms',
    '寒蝉鸣': 'Autumn cicadas chirp',
    '鹰乃祭鸟': 'Hawks hunt birds',
    '天地始肃': 'Nature turns crisp',
    '禾乃登': 'Grains ripen',
    '鸿雁来': 'Wild geese arrive',
    '玄鸟归': 'Swallows depart',
    '群鸟养羞': 'Birds store food',
    '雷始收声': 'Thunder subsides',
    '蛰虫坯户': 'Insects seal burrows',
    '水始涸': 'Waters begin drying',
    '鸿雁来宾': 'Late geese arrive',
    '雀入大水为蛤': 'Sparrows turn to clams',
    '菊有黄花': 'Chrysanthemums bloom yellow',
    '豺乃祭兽': 'Jackals store prey',
    '草木黄落': 'Leaves turn yellow and fall',
    '蛰虫咸俯': 'Insects enter hibernation',
    '水始冰': 'Water begins freezing',
    '地始冻': 'Earth begins freezing',
    '雉入大水为蜃': 'Pheasants turn to oysters',
    '虹藏不见': 'Rainbows vanish',
    '天气上升地气下降': 'Heaven rises, earth descends',
    '闭塞而成冬': 'All closes into winter',
    '鹖鴠不鸣': 'Night birds fall silent',
    '虎始交': 'Tigers mate',
    '荔挺出': 'Iris shoots emerge',
  };

  static const Map<String, String> _shenShaEn = <String, String>{
    '天恩': 'Heavenly Grace',
    '鸣吠': 'Herald Call',
    '母仓': 'Mother Granary',
    '不将': 'Non-Clashing',
    '四相': 'Four Phases',
    '鸣吠对': 'Paired Herald',
    '五合': 'Five Harmonies',
    '三合': 'Three Harmonies',
    '除神': 'Purifying Spirit',
    '月德': 'Monthly Virtue',
    '月空': 'Monthly Void',
    '月德合': 'Monthly Virtue Union',
    '月恩': 'Monthly Grace',
    '时阴': 'Timely Yin',
    '五富': 'Five Fortunes',
    '生气': 'Vital Qi',
    '金匮': 'Golden Coffer',
    '相日': 'Minister Day',
    '阴德': 'Hidden Virtue',
    '六合': 'Six Harmonies',
    '益后': 'Prospering Posterity',
    '青龙': 'Azure Dragon',
    '续世': 'Lineage Continuity',
    '明堂': 'Bright Hall',
    '王日': 'Royal Day',
    '要安': 'Peace & Safety',
    '官日': 'Official Day',
    '吉期': 'Auspicious Term',
    '福德': 'Blessed Virtue',
    '六仪': 'Six Rites',
    '金堂': 'Golden Hall',
    '宝光': 'Precious Radiance',
    '民日': 'Civic Day',
    '临日': 'Visiting Day',
    '天马': 'Celestial Steed',
    '敬安': 'Reverent Peace',
    '普护': 'Universal Protection',
    '驿马': 'Post Horse',
    '天后': 'Heavenly Empress',
    '阳德': 'Yang Virtue',
    '天喜': 'Heavenly Joy',
    '天医': 'Heavenly Physician',
    '司命': 'Life Governor',
    '圣心': 'Sacred Heart',
    '玉宇': 'Jade Canopy',
    '守日': 'Guarding Day',
    '时德': 'Timely Virtue',
    '解神': 'Resolving Spirit',
    '时阳': 'Timely Yang',
    '天仓': 'Heavenly Granary',
    '天巫': 'Heavenly Shaman',
    '玉堂': 'Jade Hall',
    '福生': 'Growing Blessing',
    '天德': 'Heavenly Virtue',
    '天德合': 'Heavenly Virtue Union',
    '天愿': 'Heavenly Wish',
    '天赦': 'Heavenly Pardon',
    '天符': 'Heavenly Talisman',
    '阴神': 'Yin Spirit',
    '解除': 'Cleansing',
    '五虚': 'Five Voids',
    '五离': 'Five Separations',
    '重日': 'Double Day',
    '复日': 'Repeating Day',
    '血支': 'Blood Branch',
    '天贼': 'Heavenly Thief',
    '土符': 'Earth Talisman',
    '游祸': 'Wandering Mishap',
    '白虎': 'White Tiger',
    '小耗': 'Minor Drain',
    '致死': 'Fatal Sha',
    '河魁': 'River Chief',
    '劫煞': 'Robbery Sha',
    '月煞': 'Monthly Sha',
    '月建': 'Monthly Establish',
    '往亡': 'Departure Loss',
    '大时': 'Great Hour Sha',
    '大败': 'Great Defeat',
    '咸池': 'Peach Pool',
    '厌对': 'Aversion Counter',
    '招摇': 'Beckoning Sha',
    '九坎': 'Nine Pits',
    '九焦': 'Nine Scorches',
    '天罡': 'Heavenly Dipper',
    '死神': 'Death Spirit',
    '月害': 'Monthly Harm',
    '死气': 'Dead Qi',
    '月破': 'Monthly Clash',
    '大耗': 'Major Drain',
    '天牢': 'Heavenly Prison',
    '元武': 'Black Tortoise',
    '玄武': 'Black Tortoise',
    '月厌': 'Monthly Aversion',
    '月虚': 'Monthly Void',
    '归忌': 'Return Taboo',
    '小时': 'Minor Hour Sha',
    '天刑': 'Heavenly Punishment',
    '朱雀': 'Vermilion Bird',
    '九空': 'Nine Voids',
    '天吏': 'Heavenly Bailiff',
    '地火': 'Earth Fire',
    '四击': 'Four Strikes',
    '大煞': 'Major Sha',
    '勾陈': 'Grappling Hook',
    '八专': 'Eight Specialties',
    '灾煞': 'Calamity Sha',
    '天火': 'Heavenly Fire',
    '血忌': 'Blood Taboo',
    '土府': 'Earth Manor',
    '月刑': 'Monthly Penalty',
    '触水龙': 'Water Dragon Clash',
    '地囊': 'Earth Sac',
    '八风': 'Eight Winds',
    '四废': 'Four Wastes',
    '四忌': 'Four Taboos',
    '四穷': 'Four Exhaustions',
    '五墓': 'Five Tombs',
    '阴错': 'Yin Error',
    '四耗': 'Four Drains',
    '阳错': 'Yang Error',
    '孤辰': 'Solitary Star',
    '小会': 'Minor Assembly',
    '大会': 'Grand Assembly',
    '八龙': 'Eight Dragons',
    '七鸟': 'Seven Birds',
    '九虎': 'Nine Tigers',
    '六蛇': 'Six Snakes',
    '天狗': 'Heavenly Hound',
    '行狠': 'Fierce March',
    '了戾': 'Perverse Sha',
    '岁薄': 'Annual Thinness',
    '逐阵': 'Chasing Array',
    '三丧': 'Triple Mourning',
    '三阴': 'Triple Yin',
    '阴道冲阳': 'Yin Clashing Yang',
    '阴位': 'Yin Position',
    '阴阳交破': 'Yin-Yang Clash',
    '阴阳俱错': 'Dual Yin-Yang Error',
    '阴阳击冲': 'Yin-Yang Strike',
    '鬼哭': 'Ghost Wail',
    '单阴': 'Single Yin',
    '绝阴': 'Exhausted Yin',
    '纯阳': 'Pure Yang',
    '阳错阴冲': 'Yang Error Yin Clash',
    '七符': 'Seven Talismans',
    '成日': 'Completion Day',
    '孤阳': 'Solitary Yang',
    '绝阳': 'Exhausted Yang',
    '纯阴': 'Pure Yin',
    '大退': 'Great Retreat',
    '四离': 'Four Separations',
    '阳破阴冲': 'Yang Break Yin Clash',
  };

  static const Map<String, String> _solarTerms = <String, String>{
    '冬至': 'Winter Solstice',
    '小寒': 'Minor Cold',
    '大寒': 'Major Cold',
    '立春': 'Start of Spring',
    '雨水': 'Rain Water',
    '惊蛰': 'Awakening of Insects',
    '春分': 'Spring Equinox',
    '清明': 'Qingming Festival',
    '谷雨': 'Grain Rain',
    '立夏': 'Start of Summer',
    '小满': 'Grain Buds',
    '芒种': 'Grain in Ear',
    '夏至': 'Summer Solstice',
    '小暑': 'Minor Heat',
    '大暑': 'Major Heat',
    '立秋': 'Start of Autumn',
    '处暑': 'End of Heat',
    '白露': 'White Dew',
    '秋分': 'Autumn Equinox',
    '寒露': 'Cold Dew',
    '霜降': 'Frost Descent',
    '立冬': 'Start of Winter',
    '小雪': 'Minor Snow',
    '大雪': 'Major Snow',
  };

  static const Map<String, String> _festivals = <String, String>{
    // Solar festivals
    '元旦': "New Year's Day",
    '元旦节': "New Year's Day",
    '情人节': "Valentine's Day",
    '妇女节': "Women's Day",
    '植树节': 'Arbor Day',
    '消费者权益日': 'Consumer Rights Day',
    '愚人节': "April Fools' Day",
    '劳动节': 'Labor Day',
    '青年节': 'Youth Day',
    '母亲节': "Mother's Day",
    '儿童节': "Children's Day",
    '父亲节': "Father's Day",
    '建党节': 'CPC Founding Day',
    '建军节': 'Army Day',
    '教师节': "Teachers' Day",
    '国庆节': 'National Day',
    '国庆中秋': 'National Day & Mid-Autumn',
    '万圣节前夜': 'Halloween',
    '万圣节': "All Saints' Day",
    '感恩节': 'Thanksgiving',
    '平安夜': 'Christmas Eve',
    '圣诞节': 'Christmas',
    '全国中小学生安全教育日': 'Student Safety Day',
    '全国助残日': 'National Disability Day',
    '全民国防教育日': 'National Defense Day',
    '世界住房日': 'World Habitat Day',
    // Lunar & traditional festivals
    '春节': 'Spring Festival',
    '元宵': 'Lantern Festival',
    '元宵节': 'Lantern Festival',
    '龙抬头': 'Dragon Head Raising',
    '龙头节': 'Dragon Head Raising',
    '寒食节': 'Cold Food Festival',
    '春社': 'Spring She Day',
    '秋社': 'Autumn She Day',
    '端午': 'Dragon Boat Festival',
    '端午节': 'Dragon Boat Festival',
    '七夕': 'Qixi Festival',
    '七夕节': 'Qixi Festival',
    '中元': 'Ghost Festival',
    '中元节': 'Ghost Festival',
    '中秋': 'Mid-Autumn Festival',
    '中秋节': 'Mid-Autumn Festival',
    '重阳': 'Double Ninth Festival',
    '重阳节': 'Double Ninth Festival',
    '腊八': 'Laba Festival',
    '腊八节': 'Laba Festival',
    '小年': 'Little New Year',
    '除夕': "New Year's Eve",
  };

  static const Map<String, String> _yiJiTerms = <String, String>{
    '祭祀': 'Worship',
    '祈福': 'Praying for blessings',
    '求嗣': 'Praying for offspring',
    '开光': 'Consecration',
    '塑绘': 'Sculpting & painting',
    '齐醮': 'Taoist ritual',
    '斋醮': 'Taoist ritual',
    '沐浴': 'Bathing',
    '酬神': 'Thanking deities',
    '造庙': 'Building temple',
    '祀灶': 'Worshiping kitchen god',
    '焚香': 'Burning incense',
    '谢土': 'Earth gratitude ceremony',
    '出火': 'Moving altar',
    '雕刻': 'Carving',
    '嫁娶': 'Marriage',
    '订婚': 'Engagement',
    '纳采': 'Betrothal',
    '问名': 'Name exchange',
    '纳婿': 'Adopting son-in-law',
    '归宁': 'Bride visiting parents',
    '安床': 'Setting bed',
    '合帐': 'Making curtains',
    '冠笄': 'Coming-of-age ceremony',
    '订盟': 'Betrothal pledge',
    '进人口': 'Adopting family member',
    '裁衣': 'Tailoring',
    '挽面': 'Facial threading',
    '开容': 'Cosmetic grooming',
    '修坟': 'Repairing tomb',
    '启钻': 'Exhuming',
    '破土': 'Breaking ground',
    '安葬': 'Burial',
    '立碑': 'Erecting monument',
    '成服': 'Mourning attire',
    '除服': 'Ending mourning',
    '开生坟': 'Building pre-tomb',
    '合寿木': 'Making coffin',
    '入殓': 'Encoffining',
    '移柩': 'Moving coffin',
    '普渡': 'Salvation ritual',
    '入宅': 'Moving into house',
    '安香': 'Placing incense altar',
    '安门': 'Installing door',
    '修造': 'Renovation',
    '起基': 'Laying foundation',
    '动土': 'Earth-breaking',
    '上梁': 'Raising ridge beam',
    '竖柱': 'Erecting pillars',
    '开井开池': 'Digging well or pond',
    '作陂放水': 'Damming & drainage',
    '拆卸': 'Demolition',
    '破屋': 'Demolishing building',
    '坏垣': 'Demolishing walls',
    '补垣': 'Repairing walls',
    '伐木做梁': 'Lumbering for beams',
    '作灶': 'Building stove',
    '解除': 'Cleansing ritual',
    '开柱眼': 'Mortising pillars',
    '穿屏扇架': 'Installing screen doors',
    '盖屋合脊': 'Roofing & ridging',
    '开厕': 'Building latrine',
    '造仓': 'Building granary',
    '塞穴': 'Filling holes',
    '平治道涂': 'Paving roads',
    '造桥': 'Building bridge',
    '作厕': 'Building latrine',
    '筑堤': 'Building dyke',
    '开池': 'Digging pond',
    '伐木': 'Lumbering',
    '开渠': 'Digging ditch',
    '掘井': 'Digging well',
    '扫舍': 'House cleaning',
    '放水': 'Water drainage',
    '造屋': 'Building house',
    '合脊': 'Setting roof ridge',
    '造畜稠': 'Building animal pen',
    '修门': 'Repairing door',
    '定磉': 'Setting plinths',
    '作梁': 'Making beam',
    '修饰垣墙': 'Plastering walls',
    '架马': 'Erecting scaffold',
    '开市': 'Opening business',
    '挂匾': 'Hanging sign',
    '纳财': 'Collecting wealth',
    '求财': 'Seeking wealth',
    '开仓': 'Opening warehouse',
    '买车': 'Buying vehicle',
    '置产': 'Acquiring property',
    '雇佣': 'Hiring',
    '出货财': 'Shipping goods',
    '安机械': 'Installing machinery',
    '造车器': 'Crafting vehicles',
    '经络': 'Weaving',
    '酝酿': 'Brewing',
    '作染': 'Dyeing',
    '鼓铸': 'Smelting & casting',
    '造船': 'Shipbuilding',
    '割蜜': 'Harvesting honey',
    '栽种': 'Planting',
    '取渔': 'Fishing',
    '结网': 'Net making',
    '牧养': 'Grazing animals',
    '安碓磑': 'Setting mill',
    '习艺': 'Learning craft',
    '入学': 'School admission',
    '理发': 'Haircut',
    '探病': 'Visiting the sick',
    '见贵': 'Meeting dignitaries',
    '乘船': 'Taking boat',
    '渡水': 'Crossing water',
    '针灸': 'Acupuncture',
    '出行': 'Travel',
    '移徙': 'Relocation',
    '分居': 'Setting up home',
    '剃头': 'Hair shaving',
    '整手足甲': 'Manicuring',
    '纳畜': 'Acquiring livestock',
    '捕捉': 'Hunting/catching',
    '畋猎': 'Hunting',
    '教牛马': 'Training livestock',
    '会亲友': 'Meeting relatives',
    '赴任': 'Taking office',
    '求医': 'Seeking medical care',
    '治病': 'Medical treatment',
    '词讼': 'Litigation',
    '起基动土': 'Laying foundation',
    '破屋坏垣': 'Demolishing structures',
    '盖屋': 'Building house',
    '造仓库': 'Building warehouse',
    '立券交易': 'Signing contracts',
    '交易': 'Trading',
    '立券': 'Signing contracts',
    '安机': 'Installing machinery',
    '会友': 'Meeting friends',
    '求医疗病': 'Seeking medical care',
    '诸事不宜': 'Unfavorable for all',
    '馀事勿取': 'Avoid other matters',
    '行丧': 'Funeral procession',
    '断蚁': 'Pest control',
    '归岫': 'Resting at home',
    '无': 'None',
  };
}
