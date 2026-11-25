import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('统计页四象限分布是可用分析卡片而不是未完成占位', () {
    final source = File(
      'lib/screens/statistics_screen.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('四象限分布 (未完成)')));
    expect(source, isNot(contains('四象限分布(未完成)')));
    expect(source, contains('_buildQuadrantStats'));
    expect(source, contains('_QuadrantDistributionCard'));
    expect(source, contains('_QuadrantDistributionRow'));
    expect(source, contains('_QuadrantMetric'));
    expect(source, contains('.quadrantTitle'));
    expect(source, contains('.quadrantSubtitle'));
    expect(source, contains('.quadrantDescription'));
    expect(source, contains('.quadrantRowSummary('));
    expect(source, contains('.quadrantRowSummary('));
    expect(source, contains('.quadrantRowSummary('));
    expect(source, contains('.quadrantRowSummary('));
  });

  test('统计页四象限分析覆盖四类行动建议', () {
    final source = File(
      'lib/screens/statistics_screen.dart',
    ).readAsStringSync();

    for (final property in [
      'quadrantUrgentImportantLabel',
      'quadrantUrgentImportantAction',
      'quadrantNotUrgentImportantLabel',
      'quadrantNotUrgentImportantAction',
      'quadrantUrgentNotImportantLabel',
      'quadrantUrgentNotImportantAction',
      'quadrantNotUrgentNotImportantLabel',
      'quadrantNotUrgentNotImportantAction',
      'quadrantUrgentImportantGuidance',
      'quadrantNotUrgentImportantGuidance',
      'quadrantUrgentNotImportantGuidance',
      'quadrantNotUrgentNotImportantGuidance',
    ]) {
      expect(source, contains('.$property'));
    }
  });
}
