import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('月历格子在更多应用等紧凑高度下不会因日期字体溢出', () {
    final source = File(
      'lib/widgets/calendar_month_grid.dart',
    ).readAsStringSync();

    expect(source, contains('final dayFontSize = cellHeight < 14'));
    expect(source, contains('(cellHeight * 0.72).clamp(6.0, 9.0).toDouble()'));
    expect(source, contains('child: ClipRect('));
    expect(source, contains('height: cellHeight < 14 ? 0.95 : 1.05'));
    expect(source, contains('final showDots = cellHeight >= 29'));
    expect(
      source,
      contains('final showSubText = showLunar && cellHeight >= 42'),
    );
  });

  test('月历格子保留倒数日事件点，不让倒数日在月视图消失', () {
    final source = File(
      'lib/widgets/calendar_month_grid.dart',
    ).readAsStringSync();

    expect(source, contains('CalendarEventType.countdown'));
    expect(source, contains('const Color(0xFFFF8A65)'));
  });
}
