/// 中文自然语言日期/时间解析（Task T-39）。
///
/// 解析常见中文日期表达，例如：
/// - "明天下午3点" → 明天 15:00
/// - "下周一上午10点" → 下周一 10:00
/// - "后天" → 后天日期（无时间）
/// - "今晚8点" → 今天 20:00
///
/// 设计目标：
/// - 纯 Dart，便于单元测试，不依赖平台。
/// - 失败时返回 [SmartDateParseResult.empty]，调用方决定降级行为。
/// - 仅做"足够好"的启发式匹配；复杂场景建议手动选择日期。
library;

class SmartDateParseResult {
  /// 解析得到的日期；时间未指定时为 null。
  final DateTime? dateTime;

  /// 解析时使用的原文片段（用于从输入中剥离）。
  final String matchedText;

  /// 是否同时解析出了小时与分钟。
  final bool hasTimeOfDay;

  const SmartDateParseResult({
    required this.dateTime,
    required this.matchedText,
    required this.hasTimeOfDay,
  });

  static const empty = SmartDateParseResult(
    dateTime: null,
    matchedText: '',
    hasTimeOfDay: false,
  );

  bool get isSuccess => dateTime != null;

  String get strippedFrom => matchedText;
}

class SmartDateParser {
  SmartDateParser._();

  /// 解析 [input] 中的中文日期/时间表达。
  static SmartDateParseResult parse(String input, {DateTime? now}) {
    if (input.trim().isEmpty) return SmartDateParseResult.empty;
    final base = now ?? DateTime.now();
    final today = DateTime(base.year, base.month, base.day);

    final m1 = _dateWithTime(input, today);
    if (m1.isSuccess) return m1;

    final m3 = _timePart(input, today);
    if (m3.isSuccess) return m3;

    // 如果输入包含明显的时间标记但解析失败 → 直接返回失败，
    // 避免将"明天99点"误判为只取"明天"。
    final hasTimeMarker = RegExp(r'\d+\s*(点|:|：)').hasMatch(input);
    if (hasTimeMarker) return SmartDateParseResult.empty;

    final m2 = _datePart(input, today);
    if (m2.isSuccess) return m2;
    return SmartDateParseResult.empty;
  }

  static SmartDateParseResult _dateWithTime(String input, DateTime today) {
    // 支持 "下周一下午3点"、"本周三上午9点半" 等组合，weekWord 紧跟在 dayWord 之后
    // 形如 "下周一" 或独立的 "周一" 都允许。
    final pattern = RegExp(
      r'(今天|明天|后天|大后天|下下周|下周|本周)?\s*'
      r'(?:(周一|周二|周三|周四|周五|周六|周日|周天)|(一|二|三|四|五|六|日|天))?\s*'
      r'(凌晨|早上|早晨|上午|中午|下午|晚上|晚)?\s*'
      r'(\d{1,2})\s*(?:点|:|：)\s*(\d{1,2})?\s*(?:分)?(半)?',
    );
    final match = pattern.firstMatch(input);
    if (match == null) return SmartDateParseResult.empty;

    final dayWord = match.group(1);
    final weekWordFull = match.group(2);
    final weekDigit = match.group(3);
    final weekWord = weekWordFull ?? (weekDigit != null ? '周$weekDigit' : null);
    final periodWord = match.group(4);
    final hourStr = match.group(5)!;
    final minuteStr = match.group(6);
    final halfMarker = match.group(7);

    if (dayWord == null && weekWord == null && periodWord == null) {
      // 仅日期 → 由 _timePart 处理
      return SmartDateParseResult.empty;
    }

    final dateBase = _resolveDate(today, dayWord, weekWord) ?? today;

    var hour = int.tryParse(hourStr) ?? -1;
    if (hour < 0 || hour > 23) return SmartDateParseResult.empty;
    var minute = int.tryParse(minuteStr ?? '0') ?? 0;
    if (halfMarker != null) minute = 30;
    if (minute < 0 || minute > 59) return SmartDateParseResult.empty;

    // 下午/晚上的小时换算
    if (periodWord != null) {
      if ((periodWord == '下午' || periodWord == '晚上' || periodWord == '晚') &&
          hour < 12) {
        hour += 12;
      } else if (periodWord == '中午' && hour < 12) {
        hour = 12;
      } else if (periodWord == '凌晨' && hour == 12) {
        hour = 0;
      }
    }

    final dt = DateTime(
      dateBase.year,
      dateBase.month,
      dateBase.day,
      hour,
      minute,
    );
    return SmartDateParseResult(
      dateTime: dt,
      matchedText: match.group(0)!,
      hasTimeOfDay: true,
    );
  }

  static SmartDateParseResult _datePart(String input, DateTime today) {
    // 1) "本周三" / "下周一" / "下下周日" — 周词在 dayWord 后紧跟一个数字字
    final combo = RegExp(
      r'(本周|下周|下下周)(一|二|三|四|五|六|日|天)',
    ).firstMatch(input);
    if (combo != null) {
      final dayWord = combo.group(1)!;
      final dayDigit = combo.group(2)!;
      final dt = _resolveDate(today, dayWord, '周$dayDigit');
      if (dt != null) {
        return SmartDateParseResult(
          dateTime: dt,
          matchedText: combo.group(0)!,
          hasTimeOfDay: false,
        );
      }
    }

    // 2) "下周" + " " + "周一" 这类显式格式 / 单独的"今天/明天/后天"等
    final pattern = RegExp(
      r'(今天|明天|后天|大后天|下下周|下周|本周)\s*(周一|周二|周三|周四|周五|周六|周日|周天)?',
    );
    final match = pattern.firstMatch(input);
    if (match == null) return SmartDateParseResult.empty;
    final dayWord = match.group(1);
    final weekWord = match.group(2);
    final dt = _resolveDate(today, dayWord, weekWord);
    if (dt == null) return SmartDateParseResult.empty;
    return SmartDateParseResult(
      dateTime: dt,
      matchedText: match.group(0)!,
      hasTimeOfDay: false,
    );
  }

  static SmartDateParseResult _timePart(String input, DateTime today) {
    // 仅时间，无日期 → 今天
    final pattern = RegExp(
      r'(凌晨|早上|早晨|上午|中午|下午|晚上|晚)?\s*(\d{1,2})\s*(?:点|:|：)\s*(\d{1,2})?\s*(?:分)?(半)?',
    );
    final match = pattern.firstMatch(input);
    if (match == null) return SmartDateParseResult.empty;
    final periodWord = match.group(1);
    var hour = int.tryParse(match.group(2)!) ?? -1;
    if (hour < 0 || hour > 23) return SmartDateParseResult.empty;
    var minute = int.tryParse(match.group(3) ?? '0') ?? 0;
    if (match.group(4) != null) minute = 30;
    if (minute < 0 || minute > 59) return SmartDateParseResult.empty;
    if (periodWord != null) {
      if ((periodWord == '下午' || periodWord == '晚上' || periodWord == '晚') &&
          hour < 12) {
        hour += 12;
      }
    }
    final dt = DateTime(today.year, today.month, today.day, hour, minute);
    return SmartDateParseResult(
      dateTime: dt,
      matchedText: match.group(0)!,
      hasTimeOfDay: true,
    );
  }

  /// 将日期词组合解析为具体 DateTime（无时间）。
  static DateTime? _resolveDate(
    DateTime today,
    String? dayWord,
    String? weekWord,
  ) {
    final weekdayMap = <String, int>{
      '周一': 1, '周二': 2, '周三': 3, '周四': 4,
      '周五': 5, '周六': 6, '周日': 7, '周天': 7,
    };

    if (weekWord != null) {
      final targetWeekday = weekdayMap[weekWord];
      if (targetWeekday == null) return null;
      final currentWeekday = today.weekday;
      // 本周一 = today + (target - current)，可能为过去日期
      // 下周一 = 下周一（=本周日 + 1） + (target - 1)
      // 下下周一 = 下下周一 + (target - 1)
      if (dayWord == '本周') {
        return today.add(Duration(days: targetWeekday - currentWeekday));
      }
      if (dayWord == '下周') {
        // 下周一的偏移 = 8 - currentWeekday（本周日是 7-currentWeekday，再 +1）
        final mondayNextWeek = 8 - currentWeekday;
        return today.add(Duration(days: mondayNextWeek + targetWeekday - 1));
      }
      if (dayWord == '下下周') {
        final mondayNextNextWeek = 8 - currentWeekday + 7;
        return today.add(
          Duration(days: mondayNextNextWeek + targetWeekday - 1),
        );
      }
      // 无 dayWord 前缀的孤立"周一" → 取最近的下一个周X
      var diff = targetWeekday - currentWeekday;
      if (diff <= 0) diff += 7;
      return today.add(Duration(days: diff));
    }

    switch (dayWord) {
      case '今天':
        return today;
      case '明天':
        return today.add(const Duration(days: 1));
      case '后天':
        return today.add(const Duration(days: 2));
      case '大后天':
        return today.add(const Duration(days: 3));
      case '本周':
      case '下周':
        return today.add(Duration(days: 8 - today.weekday));
      case '下下周':
        return today.add(Duration(days: 15 - today.weekday));
    }
    return null;
  }
}
