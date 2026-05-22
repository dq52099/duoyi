import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('Pomodoro history exposes dedicated focus report export', () {
    final screen = File('lib/screens/pomodoro_screen.dart').readAsStringSync();
    final report = File('lib/core/focus_report.dart').readAsStringSync();

    expect(screen, contains("import '../core/focus_report.dart';"));
    expect(screen, contains('复制本周专注报告'));
    expect(screen, contains('复制本月报告'));
    expect(screen, contains('FocusReportBuilder.build('));
    expect(screen, contains('FocusReportPeriod.week'));
    expect(screen, contains('FocusReportPeriod.month'));
    expect(
      screen,
      contains('Clipboard.setData(ClipboardData(text: markdown))'),
    );
    expect(screen, contains('专注报告 Markdown 已复制'));

    expect(report, contains('class FocusReport'));
    expect(report, contains('FocusTagStats.build(sessions: focusSessions'));
    expect(report, contains('penaltyAffectedSeconds'));
    expect(report, contains('String toMarkdown()'));
    expect(report, contains('## 标签投入'));
  });
}
