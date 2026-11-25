/// Saved facts are independent of the language used to view a review.
enum WeeklyReviewPeriod { thisWeek, lastWeek, custom }

class WeeklyReviewStats {
  const WeeklyReviewStats({
    required this.completedTodos,
    required this.totalTodos,
    required this.focusMinutes,
    required this.habitStreak,
    this.period = WeeklyReviewPeriod.custom,
    this.customPeriodLabel = '',
  });

  final int completedTodos;
  final int totalTodos;
  final int focusMinutes;
  final int habitStreak;
  final WeeklyReviewPeriod period;
  final String customPeriodLabel;

  String format({required bool isEnglish}) {
    final label = switch (period) {
      WeeklyReviewPeriod.thisWeek => isEnglish ? 'this week' : '本周',
      WeeklyReviewPeriod.lastWeek => isEnglish ? 'last week' : '上周',
      WeeklyReviewPeriod.custom => customPeriodLabel,
    };
    return isEnglish
        ? '$label summary: tasks done $completedTodos / $totalTodos, focus $focusMinutes min, longest habit streak $habitStreak days.'
        : '$label数据：完成 $completedTodos / $totalTodos 项待办，专注 $focusMinutes 分钟，习惯连续打卡 $habitStreak 天。';
  }

  Map<String, Object> toJson() => {
    'completedTodos': completedTodos,
    'totalTodos': totalTodos,
    'focusMinutes': focusMinutes,
    'habitStreak': habitStreak,
    'period': period.name,
    if (period == WeeklyReviewPeriod.custom)
      'customPeriodLabel': customPeriodLabel,
  };

  static WeeklyReviewStats? fromJson(Object? value) {
    if (value is! Map) return null;
    final numbers = [
      value['completedTodos'],
      value['totalTodos'],
      value['focusMinutes'],
      value['habitStreak'],
    ];
    if (numbers.any((n) => n is! int || n < 0)) return null;
    final period = switch (value['period']) {
      'thisWeek' => WeeklyReviewPeriod.thisWeek,
      'lastWeek' => WeeklyReviewPeriod.lastWeek,
      'custom' => WeeklyReviewPeriod.custom,
      _ => null,
    };
    if (period == null ||
        (period == WeeklyReviewPeriod.custom &&
            value['customPeriodLabel'] is! String)) {
      return null;
    }
    return WeeklyReviewStats(
      completedTodos: numbers[0] as int,
      totalTodos: numbers[1] as int,
      focusMinutes: numbers[2] as int,
      habitStreak: numbers[3] as int,
      period: period,
      customPeriodLabel: period == WeeklyReviewPeriod.custom
          ? value['customPeriodLabel'] as String
          : '',
    );
  }

  // Previous releases used the selected UI period label followed by a Chinese
  // generated template, including lower-case English labels. Recognize only
  // this complete template; never rewrite unknown or decorated summaries.
  static final _legacy = RegExp(
    r'(本周|上周|this week|last week)数据：完成 (0|[1-9][0-9]*) / (0|[1-9][0-9]*) 项待办，专注 (0|[1-9][0-9]*) 分钟，习惯连续打卡 (0|[1-9][0-9]*) 天。',
  );

  static WeeklyReviewStats? fromLegacy(String text) {
    final match = _legacy.matchAsPrefix(text);
    if (match == null || match.end != text.length) return null;
    final numbers = [
      for (var i = 2; i <= 5; i++) int.tryParse(match.group(i)!),
    ];
    if (numbers.any((n) => n == null)) return null;
    return WeeklyReviewStats(
      completedTodos: numbers[0]!,
      totalTodos: numbers[1]!,
      focusMinutes: numbers[2]!,
      habitStreak: numbers[3]!,
      period: {'上周', 'last week'}.contains(match.group(1))
          ? WeeklyReviewPeriod.lastWeek
          : WeeklyReviewPeriod.thisWeek,
    );
  }
}
