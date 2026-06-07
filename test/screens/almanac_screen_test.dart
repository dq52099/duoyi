import 'package:duoyi/screens/almanac_screen.dart';
import 'dart:io';
import 'package:duoyi/models/anniversary.dart';
import 'package:duoyi/models/countdown.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/countdown_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets(
    'almanac shows month summary then opens details without weather',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: AlmanacScreen(initialDate: DateTime(2026, 6, 1))),
      );
      await tester.pumpAndSettle();

      expect(find.text('万年历'), findsWidgets);
      expect(find.text('6月'), findsOneWidget);
      expect(find.text('2026年'), findsOneWidget);
      expect(find.text('四月十六'), findsOneWidget);
      expect(find.textContaining('丙午马年 癸巳月 丙午日'), findsOneWidget);
      expect(find.text('宜'), findsOneWidget);
      expect(find.text('忌'), findsOneWidget);
      expect(find.text('2026年6月1日星期一'), findsNothing);
      expect(find.text('胎神'), findsNothing);
      expect(find.text('彭祖'), findsNothing);
      expect(find.text('五行'), findsNothing);
      expect(find.text('星宿'), findsNothing);
      expect(find.text('冲煞'), findsNothing);
      expect(find.text('时辰吉凶'), findsNothing);

      await tester.tap(find.text('1').first);
      await tester.pumpAndSettle();

      expect(find.text('2026年6月1日星期一'), findsNothing);
      expect(find.text('胎神'), findsNothing);
      expect(find.text('查看黄历'), findsNothing);
      expect(
        find.byKey(const ValueKey('selected_date_almanac_summary_card')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('selected_date_almanac_summary_card')),
      );
      await tester.pumpAndSettle();

      expect(find.text('2026年6月1日星期一'), findsOneWidget);
      expect(find.text('胎神'), findsOneWidget);
      expect(find.text('彭祖'), findsOneWidget);
      expect(find.text('五行'), findsOneWidget);
      expect(find.text('星宿'), findsOneWidget);
      expect(find.text('冲煞'), findsOneWidget);
      expect(find.text('时辰吉凶'), findsNothing);
      final suitableRect = tester.getRect(find.text('宜').last);
      final avoidRect = tester.getRect(find.text('忌').last);
      expect(
        (suitableRect.center.dy - avoidRect.center.dy).abs(),
        lessThan(4),
        reason: '详细黄历中的宜和忌应在同一行展示。',
      );
      expect(
        suitableRect.right,
        lessThan(avoidRect.left),
        reason: '宜在左侧，忌在右侧。',
      );
      expect(find.textContaining('实时天气'), findsNothing);
      expect(find.textContaining('天气参考'), findsNothing);
      expect(find.textContaining('Open-Meteo'), findsNothing);
      expect(find.text('本地天气摘要'), findsNothing);
      expect(find.text('已记录天气'), findsNothing);
      expect(find.text('记录天气'), findsNothing);
      expect(find.byTooltip('记录天气'), findsNothing);
      expect(find.byTooltip('天气'), findsNothing);
      expect(find.byIcon(Icons.wb_sunny_outlined), findsNothing);
      expect(find.byIcon(Icons.cloud_outlined), findsNothing);
    },
  );

  testWidgets(
    'almanac keeps June 28 vertical suitable terms inside detail card',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(home: AlmanacScreen(initialDate: DateTime(2026, 6, 28))),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('selected_date_almanac_summary_card')),
      );
      await tester.pumpAndSettle();

      expect(find.text('2026年6月28日星期日'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('almanac_vertical_suitable_column')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('almanac_vertical_avoid_column')),
        findsOneWidget,
      );

      final suitableColumn = tester.getRect(
        find.byKey(const ValueKey('almanac_vertical_suitable_column')),
      );
      final suitableTerms = tester.getRect(
        find.byKey(const ValueKey('almanac_vertical_suitable_terms_box')),
      );
      final avoidColumn = tester.getRect(
        find.byKey(const ValueKey('almanac_vertical_avoid_column')),
      );
      final avoidTerms = tester.getRect(
        find.byKey(const ValueKey('almanac_vertical_avoid_terms_box')),
      );

      expect(suitableTerms.top, greaterThanOrEqualTo(suitableColumn.top));
      expect(
        suitableTerms.bottom,
        lessThanOrEqualTo(suitableColumn.bottom + 0.5),
      );
      expect(avoidTerms.top, greaterThanOrEqualTo(avoidColumn.top));
      expect(avoidTerms.bottom, lessThanOrEqualTo(avoidColumn.bottom + 0.5));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('almanac supports dark theme on a narrow viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: AlmanacScreen(initialDate: DateTime(2026, 6, 1)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('6月'), findsOneWidget);
    expect(find.text('四月十六'), findsOneWidget);
    expect(find.text('本月重点日期'), findsOneWidget);
    expect(find.text('胎神'), findsNothing);

    await tester.tap(find.text('1').first);
    await tester.pumpAndSettle();

    expect(find.text('2026年6月1日星期一'), findsNothing);
    expect(find.text('胎神'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('selected_date_almanac_summary_card')),
    );
    await tester.pumpAndSettle();

    expect(find.text('2026年6月1日星期一'), findsOneWidget);
    expect(find.text('胎神'), findsOneWidget);

    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();

    expect(find.text('四月十六'), findsOneWidget);
    expect(find.text('胎神'), findsNothing);
  });

  testWidgets('almanac uses lunar library instead of single-day override', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: AlmanacScreen(initialDate: DateTime(2026, 5, 31))),
    );
    await tester.pumpAndSettle();

    expect(find.text('四月十五'), findsOneWidget);
    expect(find.textContaining('丙午马年 癸巳月 乙巳日'), findsOneWidget);
    expect(find.text('胎神'), findsNothing);

    await tester.tap(find.text('31').first);
    await tester.pumpAndSettle();

    expect(find.text('2026年5月31日星期日'), findsNothing);
    expect(find.text('胎神'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('selected_date_almanac_summary_card')),
    );
    await tester.pumpAndSettle();

    expect(find.text('2026年5月31日星期日'), findsOneWidget);
    expect(find.textContaining('丙午马年 癸巳月 乙巳日'), findsWidgets);
    expect(find.text('宜'), findsWidgets);
    expect(find.text('忌'), findsWidgets);
    expect(find.text('知道了'), findsNothing);

    expect(find.textContaining('碓磨床房内东'), findsOneWidget);
    expect(find.text('覆灯火  建执位'), findsOneWidget);
    expect(find.text('蛇日冲猪（己亥）'), findsOneWidget);
    expect(find.text('煞东'), findsOneWidget);
    expect(find.textContaining('实时天气'), findsNothing);
  });

  testWidgets('almanac keeps 2026-06-03 detail fields on selected date', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: AlmanacScreen(initialDate: DateTime(2026, 6, 3))),
    );
    await tester.pumpAndSettle();

    expect(find.text('四月十八'), findsOneWidget);
    expect(find.textContaining('丙午马年 癸巳月 戊申日'), findsOneWidget);
    expect(find.text('胎神'), findsNothing);

    await tester.tap(find.text('3').first);
    await tester.pumpAndSettle();

    expect(find.text('2026年6月3日星期三'), findsNothing);
    expect(find.text('胎神'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('selected_date_almanac_summary_card')),
    );
    await tester.pumpAndSettle();

    expect(find.text('2026年6月3日星期三'), findsOneWidget);
    expect(find.textContaining('四月十八'), findsWidgets);
    expect(find.textContaining('丙午马年 癸巳月 戊申日'), findsWidgets);
    expect(find.text('宜'), findsWidgets);
    expect(find.text('忌'), findsWidgets);
    expect(find.text('知道了'), findsNothing);
    expect(find.text('祭\n祀'), findsOneWidget);
    expect(find.text('祈\n福'), findsOneWidget);
    expect(find.text('平\n治\n道\n涂'), findsNothing);

    final sacrificeText = tester.widget<Text>(find.text('祭\n祀'));
    final prayText = tester.widget<Text>(find.text('祈\n福'));
    expect(prayText.style?.fontSize, sacrificeText.style?.fontSize);

    expect(find.text('房床炉房内中'), findsOneWidget);
    expect(find.text('戊不受田'), findsOneWidget);
    expect(find.text('田主不祥'), findsOneWidget);
    expect(find.text('申不安床'), findsOneWidget);
    expect(find.text('鬼祟入房'), findsOneWidget);
    expect(find.text('戊不受田田主不祥'), findsNothing);
    expect(find.text('申不安床鬼祟入房'), findsNothing);
    expect(find.text('大驿土  平执位'), findsOneWidget);
    expect(find.textContaining('东方箕水豹-吉'), findsOneWidget);
    expect(find.text('猴日冲虎（壬寅）'), findsOneWidget);
    expect(find.text('煞南'), findsOneWidget);
    expect(find.textContaining('2026年6月2日'), findsNothing);
    expect(find.textContaining('2026年6月4日'), findsNothing);
    expect(find.textContaining('子吉 丑吉 寅凶'), findsNothing);

    final fetalGodText = tester.widget<Text>(find.text('房床炉房内中'));
    final mansionText = tester.widget<Text>(find.textContaining('东方箕水豹-吉'));
    final pengZuText = tester.widget<Text>(find.text('戊不受田'));
    final fiveElementText = tester.widget<Text>(find.text('大驿土  平执位'));
    final clashText = tester.widget<Text>(find.text('猴日冲虎（壬寅）'));
    final clashDirectionText = tester.widget<Text>(find.text('煞南'));
    expect(pengZuText.style?.fontSize, fetalGodText.style?.fontSize);
    expect(fiveElementText.style?.fontSize, fetalGodText.style?.fontSize);
    expect(clashText.style?.fontSize, fetalGodText.style?.fontSize);
    expect(clashDirectionText.style?.fontSize, clashText.style?.fontSize);
    expect(pengZuText.style?.height, greaterThan(fetalGodText.style!.height!));
    expect(pengZuText.style?.fontSize, mansionText.style?.fontSize);
    expect(clashText.maxLines, 1);
    expect(clashText.softWrap, isFalse);

    for (final branch in [
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
    ]) {
      expect(find.text(branch), findsOneWidget);
    }
    expect(find.text('23:00-00:59'), findsNothing);
    expect(find.text('21:00-22:59'), findsNothing);

    await tester.ensureVisible(find.text('子'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('子'));
    await tester.pumpAndSettle();

    expect(find.text('子时 · 吉'), findsOneWidget);
    expect(find.text('23:00-00:59'), findsOneWidget);
    expect(find.text('壬子'), findsOneWidget);
    expect(find.text('青龙'), findsOneWidget);
  });

  testWidgets('almanac shows holiday and user date month highlights', (
    tester,
  ) async {
    final countdownProvider = CountdownProvider();
    await countdownProvider.loadFromStorage();
    await countdownProvider.addItem(
      CountdownItem(
        id: 'release-countdown',
        title: '版本发布',
        targetDate: DateTime(2026, 10, 3),
      ),
    );
    final anniversaryProvider = AnniversaryProvider();
    await anniversaryProvider.loadFromStorage();
    await anniversaryProvider.add(
      Anniversary(
        id: 'birthday-october',
        title: '妈妈生日',
        originDate: DateTime(1990, 10, 5),
        type: AnniversaryType.birthday,
      ),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<CountdownProvider>.value(
            value: countdownProvider,
          ),
          ChangeNotifierProvider<AnniversaryProvider>.value(
            value: anniversaryProvider,
          ),
        ],
        child: MaterialApp(
          home: AlmanacScreen(initialDate: DateTime(2026, 10)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('本月重点日期'), findsOneWidget);
    expect(find.text('节日 · 国庆节'), findsOneWidget);
    expect(find.text('法定假日'), findsWidgets);
    expect(find.text('倒数日 · 版本发布'), findsOneWidget);
    expect(find.text('生日 · 妈妈生日'), findsOneWidget);
  });

  test('almanac detail uses vertical suitable and avoid columns', () {
    final source = File('lib/screens/almanac_screen.dart').readAsStringSync();
    final start = source.indexOf('class _VerticalYijiPanel');
    final end = source.indexOf('class _DateHeroPanel', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final section = source.substring(start, end);

    expect(section, contains('return LayoutBuilder('));
    expect(section, contains('Row('));
    expect(section, contains("title: '宜'"));
    expect(section, contains("title: '忌'"));
    expect(section, contains('_ClassicalVerticalDivider(color: lineColor)'));
    expect(section, contains('class _VerticalYijiColumn'));
  });

  test(
    'almanac month highlights include holidays and local date providers',
    () {
      final source = File('lib/screens/almanac_screen.dart').readAsStringSync();

      expect(source, contains("import '../services/holiday_calendar.dart';"));
      expect(source, contains('context.watch<CountdownProvider?>()'));
      expect(source, contains('context.watch<AnniversaryProvider?>()'));
      expect(source, contains('LunarCalendar.almanacDetail(selectedDate)'));
      expect(source, contains('final selectedDate = _date'));
      expect(source, contains('final lunar = almanacDetail.lunarDate'));
      expect(source, contains('class _MonthCalendar'));
      expect(source, contains('class _SelectedDateSummaryCard'));
      expect(source, contains('class _AlmanacDetailPage'));
      expect(source, contains('class _ClassicalAlmanacCard'));
      final monthCalendar = source.substring(
        source.indexOf('class _MonthCalendar extends StatelessWidget'),
        source.indexOf('class _MonthNavButton'),
      );
      expect(monthCalendar, isNot(contains('return AppSurfaceCard(')));
      expect(source, contains('class _MonthNavButton'));
      expect(source, contains('class _SoftAlmanacTag'));
      expect(source, contains('Navigator.of(context).push<DateTime>('));
      expect(source, contains('PageView.builder'));
      expect(source, contains('itemCount: _pageCount'));
      expect(source, contains('DateTime _clampDate(DateTime value)'));
      expect(
        source,
        contains("label: '\${day.year}年\${day.month}月\$d日 \$dayLabel'"),
      );
      expect(source, contains('Semantics('));
      expect(source, contains('button: true'));
      expect(source, contains('InkWell('));
      expect(source, contains('_detailCache.putIfAbsent'));
      expect(source, contains('onPageChanged: (page)'));
      expect(source, isNot(contains('showModalBottomSheet<void>')));
      expect(source, contains("title: '胎神'"));
      expect(source, contains('value: detail.fetalGod'));
      expect(source, contains("title: '彭祖'"));
      expect(source, contains('value: detail.pengZu'));
      expect(source, contains("title: '五行'"));
      expect(source, contains('value: detail.fiveElements'));
      expect(source, contains("title: '星宿'"));
      expect(source, contains('value: detail.mansion'));
      expect(source, contains("title: '冲煞'"));
      expect(source, contains('value: detail.clash'));
      expect(source, contains('class _ClassicalInfoTable'));
      expect(source, contains('class _ClassicalHourRow'));
      expect(source, contains('class _VerticalYijiPanel'));
      expect(source, contains('class _MonthHighlightsCard'));
      expect(source, contains("'本月重点日期'"));
      expect(source, contains("'本月暂无重点日期'"));
      expect(source, contains("'法定假日'"));
      expect(source, contains("'调休上班'"));
      expect(source, contains(r"'倒数日 · ${item.title}'"));
      expect(source, contains(r"'生日 · ${item.title}'"));
      expect(source, contains(r"'纪念日 · ${item.title}'"));
      expect(source, contains('HolidayCalendar.isHoliday(day)'));
      expect(source, contains('HolidayCalendar.isWorkMakeupDay(day)'));
    },
  );
}
