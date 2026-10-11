import 'package:test/test.dart';

import 'package:duoyi/core/lunar_calendar.dart';

void main() {
  test('闰月不重复普通农历节日', () {
    final regular = LunarCalendar.fromSolar(DateTime(2009, 5, 28));
    final leap = LunarCalendar.fromSolar(DateTime(2009, 6, 27));
    expect(regular.month, 5);
    expect(regular.day, 5);
    expect(regular.isLeapMonth, isFalse);
    expect(LunarCalendar.lunarFestival(regular), '端午');
    expect(leap.month, 5);
    expect(leap.day, 5);
    expect(leap.isLeapMonth, isTrue);
    expect(LunarCalendar.lunarFestival(leap), isNull);
  });

  test('除夕只标记腊月最后一天，兼容二十九日和三十日', () {
    expect(
      LunarCalendar.lunarFestival(
        LunarCalendar.fromSolar(DateTime(2023, 1, 20)),
      ),
      isNull,
    );
    expect(
      LunarCalendar.lunarFestival(
        LunarCalendar.fromSolar(DateTime(2023, 1, 21)),
      ),
      '除夕',
    );
    expect(
      LunarCalendar.lunarFestival(
        LunarCalendar.fromSolar(DateTime(2025, 1, 28)),
      ),
      '除夕',
    );
    expect(LunarCalendar.lunarFestival(const LunarDate(2022, 12, 31)), isNull);
  });

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

  test('Solar policy只按公历年份判断文档范围，不按lunar year判断', () {
    final fixtures = <(DateTime, bool)>[
      (DateTime(1899, 12, 31), false),
      (DateTime(1900, 1, 1), true),
      (DateTime.utc(1900, 12, 31, 23, 30), true),
      (DateTime(2099, 12, 31), true),
      (DateTime.utc(2100, 1, 1), false),
      (DateTime(1, 1, 1), false),
      (DateTime(9999, 12, 31), false),
    ];

    for (final (date, expected) in fixtures) {
      expect(
        LunarCalendar.isWithinDocumentedSolarRange(date),
        expected,
        reason: 'Solar policy for $date follows its Gregorian year',
      );
    }
  });

  test(
    'nullable conversion covers the Solar endpoints without rejecting lunar year 1899',
    () {
      final fixtures = <(DateTime, int, int, int)>[
        (DateTime(1900, 1, 1), 1899, 12, 1),
        (DateTime(1900, 1, 30), 1899, 12, 30),
        (DateTime(1900, 1, 31), 1900, 1, 1),
        (DateTime(2099, 12, 31), 2099, 11, 20),
      ];

      for (final (solarDate, year, month, day) in fixtures) {
        final lunar = LunarCalendar.tryFromSolar(solarDate);
        expect(
          lunar,
          isNotNull,
          reason: '$solarDate is convertible by the primary library',
        );
        expect(
          lunar!.year,
          year,
          reason: '$solarDate keeps its converted lunar year',
        );
        expect(
          lunar.month,
          month,
          reason: '$solarDate keeps its converted lunar month',
        );
        expect(
          lunar.day,
          day,
          reason: '$solarDate keeps its converted lunar day',
        );
        expect(lunar.isLeapMonth, isFalse);
        expect(
          LunarCalendar.isWithinDocumentedSolarRange(solarDate),
          isTrue,
          reason:
              'policy is based on Solar year ${solarDate.year}, not lunar year $year',
        );
      }
    },
  );

  test(
    'nullable conversions preserve the input civil date for UTC and local DateTime values',
    () {
      final utcInput = DateTime.utc(2026, 6, 3, 23, 30);
      final localInput = DateTime(2026, 6, 3, 23, 30);
      final expectedCivilDate = DateTime(2026, 6, 3);

      final utcLunar = LunarCalendar.tryFromSolar(utcInput);
      final localLunar = LunarCalendar.tryFromSolar(localInput);
      expect(utcLunar, isNotNull);
      expect(localLunar, isNotNull);
      for (final lunar in [utcLunar!, localLunar!]) {
        expect(lunar.year, 2026);
        expect(lunar.month, 4);
        expect(lunar.day, 18);
        expect(lunar.chineseText, '四月十八');
      }
      expect(utcLunar.year, localLunar.year);
      expect(utcLunar.month, localLunar.month);
      expect(utcLunar.day, localLunar.day);
      expect(utcLunar.isLeapMonth, localLunar.isLeapMonth);

      final utcDetail = LunarCalendar.tryAlmanacDetail(utcInput);
      final localDetail = LunarCalendar.tryAlmanacDetail(localInput);
      expect(utcDetail, isNotNull);
      expect(localDetail, isNotNull);
      for (final detail in [utcDetail!, localDetail!]) {
        expect(detail.solarDate.year, expectedCivilDate.year);
        expect(detail.solarDate.month, expectedCivilDate.month);
        expect(detail.solarDate.day, expectedCivilDate.day);
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
      }
      expect(utcDetail.solarDate.year, localDetail.solarDate.year);
      expect(utcDetail.solarDate.month, localDetail.solarDate.month);
      expect(utcDetail.solarDate.day, localDetail.solarDate.day);
      expect(
        utcDetail.lunarDate.chineseText,
        localDetail.lunarDate.chineseText,
      );
      expect(utcDetail.ganzhiLine, localDetail.ganzhiLine);
      expect(utcDetail.hourFortunes, localDetail.hourFortunes);
    },
  );

  test(
    'nullable APIs reject unconvertible cutover dates while legacy keeps its 1900 clamp',
    () {
      const legacyMinimum = LunarDate(1900, 1, 1);
      for (final date in [DateTime(1582, 10, 5), DateTime(1582, 10, 14)]) {
        expect(
          LunarCalendar.tryFromSolar(date),
          isNull,
          reason: '$date is an unsupported historical cutover date',
        );
        expect(
          LunarCalendar.tryAlmanacDetail(date),
          isNull,
          reason: '$date has no nullable almanac detail',
        );
        expect(LunarCalendar.isWithinDocumentedSolarRange(date), isFalse);

        final legacy = LunarCalendar.fromSolar(date);
        expect(legacy.year, legacyMinimum.year);
        expect(legacy.month, legacyMinimum.month);
        expect(legacy.day, legacyMinimum.day);
        expect(legacy.isLeapMonth, legacyMinimum.isLeapMonth);
      }
    },
  );

  test(
    '2100 conversion remains available beyond the documented Solar policy',
    () {
      final date = DateTime(2100, 1, 1);
      expect(LunarCalendar.isWithinDocumentedSolarRange(date), isFalse);

      final lunar = LunarCalendar.tryFromSolar(date);
      expect(lunar, isNotNull);
      expect(lunar!.year, 2099);
      expect(lunar.month, 11);
      expect(lunar.day, 21);
    },
  );

  test(
    'nullable conversion refuses a skipped local civil day when the host zone normalizes it',
    () {
      final localConstruction = DateTime(2011, 12, 30);
      final normalizedAwayFromRequestedDay =
          localConstruction.year != 2011 ||
          localConstruction.month != 12 ||
          localConstruction.day != 30;
      final utcInput = DateTime.utc(2011, 12, 30, 23, 30);

      if (normalizedAwayFromRequestedDay) {
        expect(LunarCalendar.tryFromSolar(utcInput), isNull);
        expect(LunarCalendar.tryAlmanacDetail(utcInput), isNull);
      } else {
        final lunar = LunarCalendar.tryFromSolar(utcInput);
        final detail = LunarCalendar.tryAlmanacDetail(utcInput);
        expect(lunar, isNotNull);
        expect(detail, isNotNull);
        expect(detail!.solarDate.year, 2011);
        expect(detail.solarDate.month, 12);
        expect(detail.solarDate.day, 30);
      }
    },
  );
}
