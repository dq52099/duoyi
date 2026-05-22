import 'package:test/test.dart';

import 'package:duoyi/core/focus_report.dart';
import 'package:duoyi/models/pomodoro.dart';

void main() {
  PomodoroSession session({
    required String id,
    required DateTime start,
    required int minutes,
    String? tag,
  }) {
    return PomodoroSession(
      id: id,
      startTime: start,
      endTime: start.add(Duration(minutes: minutes)),
      durationSeconds: minutes * 60,
      type: PomodoroType.focus,
      tag: tag,
    );
  }

  test('FocusReportBuilder summarizes weekly focus sessions and penalties', () {
    final now = DateTime(2026, 5, 20, 12);
    final report = FocusReportBuilder.build(
      period: FocusReportPeriod.week,
      now: now,
      sessions: [
        session(
          id: '1',
          start: DateTime(2026, 5, 18, 9),
          minutes: 25,
          tag: '学习',
        ),
        session(
          id: '2',
          start: DateTime(2026, 5, 19, 10),
          minutes: 50,
          tag: '#学习',
        ),
        session(id: '3', start: DateTime(2026, 5, 11, 10), minutes: 90),
      ],
      penalties: [
        PomodoroFocusPenalty(
          id: 'p1',
          occurredAt: DateTime(2026, 5, 19, 10, 20),
          reason: FocusPenaltyReason.pause,
          affectedSeconds: 5 * 60,
        ),
      ],
    );

    expect(report.title, '本周专注报告');
    expect(report.sessionCount, 2);
    expect(report.totalMinutes, 75);
    expect(report.averageMinutes, 37);
    expect(report.longestMinutes, 50);
    expect(report.activeDays, 2);
    expect(report.penaltyCount, 1);
    expect(report.penaltyAffectedMinutes, 5);
    expect(report.topTags.single.tag, '学习');
    expect(report.topTags.single.totalMinutes, 75);
  });

  test('FocusReport renders a Markdown export template', () {
    final report = FocusReportBuilder.build(
      period: FocusReportPeriod.month,
      now: DateTime(2026, 5, 20),
      sessions: [
        session(id: '1', start: DateTime(2026, 5, 2), minutes: 30, tag: '工作'),
      ],
      penalties: const [],
    );

    final markdown = report.toMarkdown();

    expect(markdown, contains('# 本月专注报告'));
    expect(markdown, contains('- 专注总时长：30 分钟'));
    expect(markdown, contains('- 工作：30 分钟 / 1 次'));
  });
}
