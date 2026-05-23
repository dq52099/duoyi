import 'package:test/test.dart';

import 'package:duoyi/core/lunar_calendar.dart';

void main() {
  test('农历转换在公历支持边界外不会数组越界', () {
    for (final date in [
      DateTime(1899, 12, 31),
      DateTime(1900, 1, 1),
      DateTime(1900, 1, 30),
      DateTime(1900, 1, 31),
      DateTime(2100, 12, 31),
      DateTime(2200, 1, 1),
    ]) {
      expect(
        () => LunarCalendar.fromSolar(date).chineseText,
        returnsNormally,
        reason: '$date should not crash lunar rendering',
      );
    }
  });

  test('农历日名对非法日期返回空文本', () {
    expect(LunarCalendar.dayName(-1), '');
    expect(LunarCalendar.dayName(0), '');
    expect(LunarCalendar.dayName(31), '');
  });
}
