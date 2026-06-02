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

  test('2026-06-03 黄历详情全部来自同一个选中日期', () {
    final date = DateTime.utc(2026, 6, 3, 23, 30);
    final detail = LunarCalendar.almanacDetail(date);
    final hours = detail.hourFortuneItems;

    expect(detail.solarDate, DateTime(2026, 6, 3));
    expect(detail.lunarDate.chineseText, '四月十八');
    expect(detail.ganzhiLine, '丙午马年癸巳月戊申日');
    expect(detail.dayGanzhi, '戊申');
    expect(detail.suitable, '祭祀 沐浴 移徙 破土 安葬 扫舍 平治道涂');
    expect(detail.avoid, '祈福 嫁娶 入宅 安床 作灶');
    expect(detail.fetalGod, '房床炉房内中');
    expect(detail.pengZu, '戊不受田，田主不祥；申不安床，鬼祟入房');
    expect(detail.fiveElements, '大驿土平执位');
    expect(detail.mansion, '东方箕水豹-吉');
    expect(detail.clash, '猴日冲虎（壬寅）煞南');
    expect(detail.hourFortunes, '子吉 丑吉 寅凶 卯凶 辰吉 巳吉 午凶 未吉 申凶 酉凶 戌吉 亥凶');
    expect(hours, hasLength(12));
    expect(hours.map((item) => item.branch), [
      '子',
      '丑',
      '寅',
      '卯',
      '辰',
      '巳',
      '午',
      '未',
      '申',
      '酉',
      '戌',
      '亥',
    ]);
    expect(hours.map((item) => item.range), [
      '23:00-00:59',
      '01:00-02:59',
      '03:00-04:59',
      '05:00-06:59',
      '07:00-08:59',
      '09:00-10:59',
      '11:00-12:59',
      '13:00-14:59',
      '15:00-16:59',
      '17:00-18:59',
      '19:00-20:59',
      '21:00-22:59',
    ]);
    expect(
      hours.map(
        (item) => '${item.ganzhi}${item.deity}${item.isAuspicious ? '吉' : '凶'}',
      ),
      [
        '壬子青龙吉',
        '癸丑明堂吉',
        '甲寅天刑凶',
        '乙卯朱雀凶',
        '丙辰金匮吉',
        '丁巳天德吉',
        '戊午白虎凶',
        '己未玉堂吉',
        '庚申天牢凶',
        '辛酉玄武凶',
        '壬戌司命吉',
        '癸亥勾陈凶',
      ],
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
