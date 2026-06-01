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

  testWidgets('almanac shows date details without weather content', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: AlmanacScreen(initialDate: DateTime(2026, 7, 1))),
    );
    await tester.pumpAndSettle();

    expect(find.text('万年历'), findsWidgets);
    expect(find.text('2026年7月1日 星期三'), findsOneWidget);
    expect(find.textContaining('农历'), findsWidgets);
    expect(find.textContaining('马年'), findsOneWidget);
    expect(find.text('宜'), findsOneWidget);
    expect(find.text('忌'), findsOneWidget);
    expect(find.text('胎神'), findsOneWidget);
    expect(find.text('彭祖'), findsOneWidget);
    expect(find.text('五行'), findsOneWidget);
    expect(find.text('星宿'), findsOneWidget);
    expect(find.text('冲煞'), findsOneWidget);
    expect(find.text('时辰吉凶'), findsOneWidget);
    final suitableRect = tester.getRect(find.text('宜'));
    final avoidRect = tester.getRect(find.text('忌'));
    expect(
      (suitableRect.center.dy - avoidRect.center.dy).abs(),
      lessThan(4),
      reason: '宜和忌应在同一行展示。',
    );
    expect(suitableRect.right, lessThan(avoidRect.left), reason: '宜在左侧，忌在右侧。');
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
  });

  testWidgets('almanac uses lunar library instead of single-day override', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: AlmanacScreen(initialDate: DateTime(2026, 5, 31))),
    );
    await tester.pumpAndSettle();

    expect(find.text('2026年5月31日 星期日'), findsOneWidget);
    expect(find.textContaining('丙午马年癸巳月乙巳日'), findsOneWidget);
    expect(find.textContaining('祭祀 解除 断蚁 会亲友 馀事勿取'), findsOneWidget);
    expect(find.textContaining('嫁娶 安葬'), findsOneWidget);
    expect(find.textContaining('碓磨床房内东'), findsOneWidget);
    expect(find.textContaining('蛇日冲猪（己亥）煞东'), findsOneWidget);
    expect(find.textContaining('实时天气'), findsNothing);
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

  test('almanac suitable and avoid sections stay in one row', () {
    final source = File('lib/screens/almanac_screen.dart').readAsStringSync();
    final start = source.indexOf('Widget _yijiRow');
    final end = source.indexOf(
      'List<_MonthHighlight> _buildMonthHighlights',
      start,
    );
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final method = source.substring(start, end);

    expect(method, contains('return Row('));
    expect(method, contains("title: '宜'"));
    expect(method, contains("title: '忌'"));
    expect(method, contains('const SizedBox(width: 10)'));
    expect(method, isNot(contains('return Column(')));
  });

  test(
    'almanac month highlights include holidays and local date providers',
    () {
      final source = File('lib/screens/almanac_screen.dart').readAsStringSync();

      expect(source, contains("import '../services/holiday_calendar.dart';"));
      expect(source, contains('context.watch<CountdownProvider?>()'));
      expect(source, contains('context.watch<AnniversaryProvider?>()'));
      expect(source, contains('LunarCalendar.almanacDetail(_date)'));
      expect(source, contains("('胎神', detail.fetalGod)"));
      expect(source, contains("('彭祖', detail.pengZu)"));
      expect(source, contains("('五行', detail.fiveElements)"));
      expect(source, contains("('星宿', detail.mansion)"));
      expect(source, contains("('冲煞', detail.clash)"));
      expect(source, contains("('时辰吉凶', detail.hourFortunes)"));
      expect(source, contains('Widget _yijiRow'));
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
