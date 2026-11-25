import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('统计页展示专注标签排行', () {
    final source = File(
      'lib/screens/statistics_screen.dart',
    ).readAsStringSync();

    expect(source, contains("import '../core/focus_tag_stats.dart';"));
    expect(source, contains('FocusTagStats.build'));
    expect(source, contains('FocusTagStats.buildTrend'));
    expect(source, contains('_buildFocusTagRankingCard'));
    expect(source, contains('_buildFocusTagShare'));
    expect(source, contains('_buildFocusTagTrendCard'));
    expect(source, contains('_buildFocusTagTrendChart'));
    expect(source, contains('.focusTagRanking'));
    expect(source, contains('.focusTagTrend'));
    expect(source, contains('.noFocusTagData'));
    expect(source, contains('.noFocusTagTrend'));
    expect(source, contains('LinearProgressIndicator'));
    expect(source, contains('LineChartData'));
    expect(source, contains('FocusTagTrendBucket.month'));
  });
}
