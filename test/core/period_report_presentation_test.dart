import 'package:duoyi/core/period_report.dart';
import 'package:duoyi/core/period_report_presentation.dart';
import 'package:test/test.dart';

void main() {
  final report = PeriodReport(
    start: DateTime(2026, 10, 1),
    end: DateTime(2026, 10, 7),
    todosCreated: 5,
    todosCompleted: 3,
    habitCheckIns: 4,
    longestHabitStreak: 2,
    focusSessions: 2,
    focusSeconds: 3600,
    timeEntrySeconds: 7200,
    timeEntryByCategory: {'原始类别 / literal': 7200},
  );
  final digest = PeriodReportDigest(
    kind: PeriodReportKind.weekly,
    report: report,
    comparison: ReportComparison.compare(current: report, previous: report),
    generatedAt: DateTime(2026, 10, 7),
  );
  test(
    'English report framing preserves numbers and literal category data',
    () {
      final text = PeriodReportPresentation(
        digest,
        isEnglish: true,
      ).toMarkdown();
      expect(text, contains('# Weekly report'));
      expect(text, contains('- Tasks completed: 3'));
      expect(text, contains('- Focus time: 60 min'));
      expect(text, contains('- 原始类别 / literal: 120 min'));
      expect(text, contains('unchanged from previous period'));
      expect(text, isNot(contains('## 摘要')));
    },
  );
  test('Chinese output keeps the existing report contract', () {
    expect(
      PeriodReportPresentation(digest, isEnglish: false).toMarkdown(),
      digest.toMarkdown(),
    );
  });

  for (final kind in PeriodReportKind.values) {
    for (final english in [false, true]) {
      test(
        '${kind.name} notification titles and empty copy in ${english ? 'en' : 'zh'}',
        () {
          final empty = _report();
          final emptyDigest = _digest(kind, empty, empty);
          final copy = PeriodReportPresentation(
            emptyDigest,
            isEnglish: english,
          );
          expect(
            copy.notificationTitle,
            PeriodReportPresentation.notificationTitleFor(
              kind,
              isEnglish: english,
            ),
          );
          if (english) {
            expect(copy.notificationTitle, contains('Duoyi'));
            expect(copy.notificationBody, switch (kind) {
              PeriodReportKind.daily =>
                'No records today. Open Duoyi to plan tomorrow',
              PeriodReportKind.weekly =>
                'No records last week. Open Duoyi to plan this week',
              PeriodReportKind.monthly =>
                'No records last month. Open Duoyi to plan this month',
              PeriodReportKind.yearly =>
                'No records for the year. Open Duoyi to start a new plan',
            });
            expect(
              copy.notificationBody,
              isNot(matches(RegExp(r'[\u4e00-\u9fff]'))),
            );
          } else {
            expect(copy.notificationBody, emptyDigest.notificationBody);
            expect(copy.notificationTitle, endsWith('已生成'));
          }
        },
      );
    }
  }

  for (final (minutes, formatted) in [
    (59, '59 min'),
    (60, '1 h'),
    (61, '1 h 1 min'),
  ]) {
    test(
      'notification duration at $minutes minutes preserves both metrics',
      () {
        final current = _report(minutes: minutes, completed: 1, habits: 1);
        final value = _digest(PeriodReportKind.daily, current, current);
        final copy = PeriodReportPresentation(value, isEnglish: true);
        expect(copy.notificationBody, contains('Focus $formatted'));
        expect(copy.notificationBody, contains('Time logged $formatted'));
        expect(copy.notificationBody, contains('Completed 1/2 tasks'));
        expect(copy.notificationBody, contains('Habits 1 check-in'));
        expect(copy.notificationBody, isNot(contains('vs previous period')));
        expect(
          PeriodReportPresentation(value, isEnglish: false).notificationBody,
          value.notificationBody,
        );
      },
    );
  }

  for (final trend in ['up', 'down', 'flat']) {
    test('notification productivity trend $trend and language stay frozen', () {
      final high = _report(minutes: 61, completed: 2, habits: 2);
      final low = _report(completed: 1);
      final current = trend == 'down' ? low : high;
      final previous = trend == 'up' ? low : high;
      final value = _digest(PeriodReportKind.weekly, current, previous);
      final english = PeriodReportPresentation(value, isEnglish: true);
      final chinese = PeriodReportPresentation(value, isEnglish: false);
      final body = english.notificationBody;
      final delta = value.comparison.productivityScore.difference.round();
      if (trend == 'flat') {
        expect(body, isNot(contains('vs previous period')));
      } else {
        expect(
          body,
          contains(
            'vs previous period ${delta > 0 ? '+' : '-'}${delta.abs()} pts',
          ),
        );
      }
      expect(chinese.notificationBody, value.notificationBody);
      expect(english.notificationBody, body);
      expect(body, contains('Productivity ${current.productivityScore}/100'));
    });
  }
}

PeriodReport _report({int minutes = 0, int completed = 0, int habits = 0}) =>
    PeriodReport(
      start: DateTime(2026, 10, 1),
      end: DateTime(2026, 10, 1),
      todosCreated: completed == 0 ? 0 : 2,
      todosCompleted: completed,
      habitCheckIns: habits,
      longestHabitStreak: habits > 0 ? 1 : 0,
      focusSessions: minutes > 0 ? 1 : 0,
      focusSeconds: minutes * 60,
      timeEntrySeconds: minutes * 60,
    );

PeriodReportDigest _digest(
  PeriodReportKind kind,
  PeriodReport current,
  PeriodReport previous,
) => PeriodReportDigest(
  kind: kind,
  report: current,
  comparison: ReportComparison.compare(current: current, previous: previous),
  generatedAt: DateTime(2026, 10, 1),
);
