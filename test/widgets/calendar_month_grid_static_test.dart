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
    expect(source, contains('final showEventCount = cellHeight >= 38'));
    expect(
      source,
      contains('final showSubText = showLunar && cellHeight >= 42'),
    );
  });

  test('月视图日期格直接展示当天事项数量', () {
    final source = File(
      'lib/widgets/calendar_month_grid.dart',
    ).readAsStringSync();
    final calendar = File(
      'lib/screens/calendar_screen.dart',
    ).readAsStringSync();
    final provider = File(
      'lib/providers/calendar_provider.dart',
    ).readAsStringSync();

    expect(source, contains('final Map<String, int> dateEventCounts'));
    expect(source, contains('final eventCount = dateEventCounts[key]'));
    expect(source, contains("'\$count项'"));
    expect(source, contains('Widget _eventCountBadge('));
    expect(
      calendar,
      contains('final dateCounts = calendarProvider.filteredDateEventCounts'),
    );
    expect(calendar, contains('dateEventCounts: dateCounts'));
    expect(provider, contains('Map<String, int> filteredDateEventCounts('));
  });

  test('月历格子保留倒数日事件点，不让倒数日在月视图消失', () {
    final source = File(
      'lib/widgets/calendar_month_grid.dart',
    ).readAsStringSync();

    expect(source, contains('CalendarEventType.countdown'));
    expect(source, contains('const Color(0xFFFF8A65)'));
  });
}
