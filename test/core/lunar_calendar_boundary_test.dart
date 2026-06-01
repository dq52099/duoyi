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

  test('黄历详情使用本地确定性规则生成完整字段', () {
    final date = DateTime(2026, 5, 31);
    final detail = LunarCalendar.almanacDetail(date);
    final hours = LunarCalendar.hourFortunes(date);

    expect(detail.dayGanzhi, isNotEmpty);
    expect(detail.fetalGod, isNotEmpty);
    expect(detail.pengZu, contains('；'));
    expect(detail.fiveElements, contains('纳音'));
    expect(detail.mansion, isNotEmpty);
    expect(detail.clash, startsWith('冲'));
    expect(detail.hourFortunes.split(' '), hasLength(12));
    expect(hours, hasLength(12));
    expect(hours.where((item) => item.isAuspicious), hasLength(6));
    expect(
      hours.map((item) => item.compactLabel).join(' '),
      detail.hourFortunes,
    );
  });
}
