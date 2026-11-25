import 'period_report.dart';

/// Frozen report language for display, clipboard and exports. No Flutter state.
class PeriodReportPresentation {
  const PeriodReportPresentation(this.digest, {required this.isEnglish});

  final PeriodReportDigest digest;
  final bool isEnglish;

  String get notificationTitle =>
      notificationTitleFor(digest.kind, isEnglish: isEnglish);

  static String notificationTitleFor(
    PeriodReportKind kind, {
    required bool isEnglish,
  }) => isEnglish
      ? switch (kind) {
          PeriodReportKind.daily => 'Duoyi daily review is ready',
          PeriodReportKind.weekly => 'Duoyi weekly report is ready',
          PeriodReportKind.monthly => 'Duoyi monthly report is ready',
          PeriodReportKind.yearly => 'Duoyi annual report is ready',
        }
      : switch (kind) {
          PeriodReportKind.daily => '多仪每日复盘已生成',
          PeriodReportKind.weekly => '多仪周报已生成',
          PeriodReportKind.monthly => '多仪月报已生成',
          PeriodReportKind.yearly => '多仪年度报告已生成',
        };

  String get notificationBody {
    if (!isEnglish) return digest.notificationBody;
    final report = digest.report;
    if (!report.hasAnyActivity) {
      return switch (digest.kind) {
        PeriodReportKind.daily =>
          'No records today. Open Duoyi to plan tomorrow',
        PeriodReportKind.weekly =>
          'No records last week. Open Duoyi to plan this week',
        PeriodReportKind.monthly =>
          'No records last month. Open Duoyi to plan this month',
        PeriodReportKind.yearly =>
          'No records for the year. Open Duoyi to start a new plan',
      };
    }
    final scoreDelta = digest.comparison.productivityScore.difference.round();
    final pieces = [
      'Productivity ${report.productivityScore}/100',
      'Completed ${report.todosCompleted}/${report.todosCreated} tasks',
      if (report.focusMinutes > 0)
        'Focus ${_compactMinutes(report.focusMinutes)}',
      if (report.habitCheckIns > 0)
        'Habits ${report.habitCheckIns} ${report.habitCheckIns == 1 ? 'check-in' : 'check-ins'}',
      if (report.timeEntryMinutes > 0)
        'Time logged ${_compactMinutes(report.timeEntryMinutes)}',
      if (scoreDelta != 0)
        'vs previous period ${scoreDelta > 0 ? '+' : '-'}${scoreDelta.abs()} pts',
    ];
    return pieces.join(' · ');
  }

  static String _compactMinutes(int minutes) {
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final remainder = minutes % 60;
    return remainder == 0 ? '$hours h' : '$hours h $remainder min';
  }

  String get title => !isEnglish
      ? digest.title
      : switch (digest.kind) {
          PeriodReportKind.daily => 'Daily review',
          PeriodReportKind.weekly => 'Weekly report',
          PeriodReportKind.monthly => 'Monthly report',
          PeriodReportKind.yearly => 'Annual report',
        };

  String get subtitle => !isEnglish
      ? digest.subtitle
      : switch (digest.kind) {
          PeriodReportKind.daily => 'Today’s productivity review',
          PeriodReportKind.weekly =>
            'Productivity over ${digest.report.dayCount} days',
          PeriodReportKind.monthly =>
            'Time invested over ${digest.report.dayCount} days',
          PeriodReportKind.yearly => 'Growth and key achievements this year',
        };

  List<String> get highlights {
    if (!isEnglish) return digest.highlights;
    final report = digest.report;
    final comparison = digest.comparison;
    return [
      'Productivity ${report.productivityScore}/100; ${_scoreLabel(report.productivityScore)}',
      '${report.todosCompleted} tasks completed; ${_delta(comparison.todosCompleted, 'tasks')}',
      '${report.focusMinutes} min focused; ${_delta(comparison.focusMinutes, 'min')}',
      '${report.habitCheckIns} habit check-ins; longest streak ${report.longestHabitStreak} days',
      if (report.timeEntryMinutes > 0)
        '${report.timeEntryMinutes} min logged across ${report.timeEntryByCategory.length} categories',
    ];
  }

  String toMarkdown({
    String Function(DateTime)? formatDate,
    String Function(Object)? formatCategory,
  }) {
    if (!isEnglish) {
      return digest.toMarkdown(
        formatDate: formatDate,
        formatCategory: formatCategory,
      );
    }
    final dateText = formatDate ?? _date;
    final categoryText = formatCategory ?? (category) => category.toString();
    final report = digest.report;
    final comparison = digest.comparison;
    final categories =
        report.timeEntryByCategory.entries
            .where((entry) => entry.value > 0)
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    final buffer = StringBuffer()
      ..writeln('# $title')
      ..writeln()
      ..writeln('Range: ${dateText(report.start)} - ${dateText(report.end)}')
      ..writeln('Generated: ${dateText(digest.generatedAt)}')
      ..writeln()
      ..writeln('## Summary');
    for (final line in highlights) {
      buffer.writeln('- $line');
    }
    buffer
      ..writeln()
      ..writeln('## Key metrics')
      ..writeln('- Tasks created: ${report.todosCreated}')
      ..writeln('- Tasks completed: ${report.todosCompleted}')
      ..writeln(
        '- Completion rate: ${(report.todoCompletionRate * 100).round()}%',
      )
      ..writeln('- Focus sessions: ${report.focusSessions}')
      ..writeln('- Focus time: ${report.focusMinutes} min')
      ..writeln('- Habit check-ins: ${report.habitCheckIns}')
      ..writeln('- Longest habit streak: ${report.longestHabitStreak} days')
      ..writeln('- Time logged: ${report.timeEntryMinutes} min')
      ..writeln()
      ..writeln('## Changes from previous period')
      ..writeln(
        '- Tasks completed: ${_delta(comparison.todosCompleted, 'tasks')}',
      )
      ..writeln('- Focus time: ${_delta(comparison.focusMinutes, 'min')}')
      ..writeln(
        '- Habit check-ins: ${_delta(comparison.habitCheckIns, 'check-ins')}',
      )
      ..writeln(
        '- Productivity: ${_delta(comparison.productivityScore, 'pts')}',
      );
    if (categories.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('## Top time investments');
      for (final entry in categories.take(5)) {
        buffer.writeln(
          '- ${categoryText(entry.key)}: ${(entry.value / 60).round()} min',
        );
      }
    }
    return buffer.toString();
  }

  static String _scoreLabel(int score) => score >= 85
      ? 'strong momentum'
      : score >= 65
      ? 'steady progress'
      : score >= 40
      ? 'room to improve'
      : 'reduce friction and rebuild with small steps';

  static String _delta(ReportMetricDelta delta, String unit) {
    final value = delta.difference.round();
    if (value == 0) return 'unchanged from previous period';
    final percent = delta.percentChangeRounded;
    return '${value.abs()} $unit ${value > 0 ? 'more' : 'fewer'} than previous period'
        '${percent == null ? '' : ' (${percent.abs()}%)'}';
  }

  static String _date(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}
