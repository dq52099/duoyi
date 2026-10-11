/// Locale-aware formatting for lunar calendar, solar terms, festivals,
/// and almanac (Yi/Ji) activities.
library;

import 'i18n.dart';
import 'lunar_calendar.dart';

class AlmanacLocaleFormat {
  AlmanacLocaleFormat._();

  static bool get isEn => I18n.current == AppLocale.en;
  static bool get isZh => I18n.current == AppLocale.zh;

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
      return '${terms.take(maxTerms).join(' ')} …';
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
    return '${translated.take(maxTerms).join(', ')} …';
  }

  /// Checks if a cultural activity term is in our curated dictionary.
  static bool isKnownYiJi(String term) => _yiJiTerms.containsKey(term.trim());

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

  // ---------------------------------------------------------------------------
  // Dictionaries
  // ---------------------------------------------------------------------------

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
    '情人节': "Valentine's Day",
    '妇女节': "Women's Day",
    '植树节': 'Arbor Day',
    '愚人节': "April Fools' Day",
    '劳动节': 'Labor Day',
    '青年节': 'Youth Day',
    '儿童节': "Children's Day",
    '建党节': 'CPC Founding Day',
    '建军节': 'Army Day',
    '教师节': "Teachers' Day",
    '国庆节': 'National Day',
    '平安夜': 'Christmas Eve',
    '圣诞节': 'Christmas',
    // Lunar festivals
    '春节': 'Spring Festival',
    '元宵': 'Lantern Festival',
    '龙抬头': 'Dragon Head Raising',
    '端午': 'Dragon Boat Festival',
    '七夕': 'Qixi Festival',
    '中元': 'Ghost Festival',
    '中秋': 'Mid-Autumn Festival',
    '重阳': 'Double Ninth Festival',
    '腊八': 'Laba Festival',
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
