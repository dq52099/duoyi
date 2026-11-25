import '../models/pomodoro.dart';
import 'focus_report.dart';
import 'focus_tag_stats.dart';
import 'i18n.dart';

/// Pure localized presentation adapter over an already built [FocusReport].
class FocusReportPresentation {
  final FocusReport report;
  final bool isEnglish;
  final bool hasAuthoredUntaggedCollision;

  const FocusReportPresentation(
    this.report, {
    this.isEnglish = false,
    this.hasAuthoredUntaggedCollision = false,
  });

  factory FocusReportPresentation.forLocale(
    FocusReport report, {
    required AppLocale locale,
    bool hasAuthoredUntaggedCollision = false,
  }) => FocusReportPresentation(
    report,
    isEnglish: locale == AppLocale.en,
    hasAuthoredUntaggedCollision: hasAuthoredUntaggedCollision,
  );

  String get title => isEnglish
      ? switch (report.period) {
          FocusReportPeriod.week => 'Weekly Focus Report',
          FocusReportPeriod.month => 'Monthly Focus Report',
          FocusReportPeriod.all => 'All Focus Report',
        }
      : report.title;

  String toMarkdown({String Function(DateTime)? formatDate}) {
    if (!isEnglish) {
      return report.toMarkdown(formatDate: formatDate);
    }
    final dateLabel = formatDate ?? _defaultDateLabel;
    final buffer = StringBuffer()
      ..writeln('# $title')
      ..writeln()
      ..writeln(
        '- Period: ${dateLabel(report.start)} - ${dateLabel(report.end)}',
      )
      ..writeln('- Total focus duration: ${report.totalMinutes} min')
      ..writeln('- Focus sessions: ${report.sessionCount}')
      ..writeln('- Average session: ${report.averageMinutes} min')
      ..writeln('- Longest session: ${report.longestMinutes} min')
      ..writeln('- Active days: ${report.activeDays}')
      ..writeln(
        '- Strict-focus interruptions: ${report.penaltyCount}, affecting ${report.penaltyAffectedMinutes} min',
      );
    if (report.topTags.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('## Tag breakdown');
      for (final tag in report.topTags) {
        final displayTag = _displayTag(tag.tag);
        buffer.writeln(
          '- $displayTag: ${tag.totalMinutes} min / ${tag.sessionCount} ${tag.sessionCount == 1 ? 'session' : 'sessions'}, share ${(tag.share * 100).round()}%',
        );
      }
    }
    return buffer.toString();
  }

  String _displayTag(String tag) {
    if (!isEnglish) return tag;
    if (tag == FocusTagStats.untaggedLabel && !hasAuthoredUntaggedCollision) {
      return 'Untagged';
    }
    return tag;
  }

  /// Detects whether any contributing in-period focus session has an authored
  /// tag that normalizes to [FocusTagStats.untaggedLabel].
  static bool detectAuthoredUntaggedCollision({
    required FocusReport report,
    required Iterable<PomodoroSession> sessions,
  }) {
    final endExclusive = DateTime(
      report.end.year,
      report.end.month,
      report.end.day,
    ).add(const Duration(days: 1));
    for (final session in sessions) {
      if (session.type != PomodoroType.focus || session.durationSeconds <= 0) {
        continue;
      }
      if (session.startTime.isBefore(report.start) ||
          !session.startTime.isBefore(endExclusive)) {
        continue;
      }
      final raw = session.tag?.trim().replaceFirst(RegExp(r'^#'), '') ?? '';
      if (raw == FocusTagStats.untaggedLabel) {
        return true;
      }
    }
    return false;
  }

  static String _defaultDateLabel(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
