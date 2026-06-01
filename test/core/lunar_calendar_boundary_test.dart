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

  test('黄历详情使用 lunar 库生成完整字段', () {
    final date = DateTime(2026, 5, 31);
    final detail = LunarCalendar.almanacDetail(date);
    final hours = LunarCalendar.hourFortunes(date);

    expect(detail.dayGanzhi, isNotEmpty);
    expect(detail.fetalGod, isNotEmpty);
    expect(detail.pengZu, contains('；'));
    expect(detail.fiveElements, contains('执位'));
    expect(detail.mansion, isNotEmpty);
    expect(detail.clash, contains('冲'));
    expect(detail.hourFortunes.split(' '), hasLength(12));
    expect(hours, hasLength(12));
    expect(hours.where((item) => item.isAuspicious), hasLength(6));
    expect(
      hours.map((item) => item.compactLabel).join(' '),
      detail.hourFortunes,
    );
  });

  test('黄历不再使用简版轮换文案或单日硬编码', () {
    final date = DateTime(2026, 5, 31);
    final lunar = LunarCalendar.fromSolar(date);
    final detail = LunarCalendar.almanacDetail(date);

    expect(LunarCalendar.suitable(date), '祭祀 解除 断蚁 会亲友 馀事勿取');
    expect(LunarCalendar.avoid(date), '嫁娶 安葬');
    expect(LunarCalendar.almanacGanzhiLine(date, lunar), '丙午马年癸巳月乙巳日');
    expect(detail.fetalGod, '碓磨床房内东');
    expect(detail.fiveElements, '覆灯火建执位');
    expect(detail.mansion, '东方房日兔-吉');
    expect(detail.clash, '蛇日冲猪（己亥）煞东');
    expect(detail.hourFortunes.split(' '), hasLength(12));
  });
}
