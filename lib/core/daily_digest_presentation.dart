/// Copy frozen to the language of one daily reminder registration.
class DailyDigestPresentation {
  const DailyDigestPresentation({required this.isEnglish});

  final bool isEnglish;

  String slotTitle(int index) {
    if (isEnglish) return 'Daily reminder ${index + 1}';
    const labels = ['一', '二', '三'];
    return '每日提醒${index < labels.length ? labels[index] : index + 1}';
  }

  String body({
    required int todayCount,
    required int tomorrowCount,
    required int overdueCount,
    required bool includeTodayTasks,
    required bool includeTomorrowPlan,
    required bool includeOverdue,
  }) {
    String count(String english, String chinese, int value) => isEnglish
        ? '$english $value ${value == 1 ? 'task' : 'tasks'}'
        : '$chinese $value 项';
    final pieces = [
      if (includeTodayTasks) count('Today', '今日', todayCount),
      if (includeTomorrowPlan) count('Tomorrow', '明日', tomorrowCount),
      if (includeOverdue) count('Overdue', '逾期', overdueCount),
    ];
    return pieces.isNotEmpty
        ? pieces.join(' · ')
        : isEnglish
        ? 'Open Duoyi to organize tasks and plans'
        : '打开多仪整理任务与计划';
  }
}
