import 'package:duoyi/core/almanac_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/i18n_date_format.dart';
import 'package:duoyi/core/lunar_calendar.dart';
import 'package:duoyi/models/anniversary.dart';
import 'package:duoyi/models/countdown.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/countdown_provider.dart';
import 'package:duoyi/screens/almanac_screen.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppLocale originalLocale;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    originalLocale = I18n.current;
    I18n.setLocale(AppLocale.zh);
  });

  tearDown(() => I18n.setLocale(originalLocale));

  testWidgets(
    'almanac and opened detail retain the selected date across zh-en-zh',
    (tester) async {
      final countdownProvider = CountdownProvider();
      await countdownProvider.loadFromStorage();
      await countdownProvider.addItem(
        CountdownItem(
          id: 'locale-countdown',
          title: 'Release plan',
          targetDate: DateTime(2026, 6, 3),
        ),
      );
      final anniversaryProvider = AnniversaryProvider();
      await anniversaryProvider.loadFromStorage();
      await anniversaryProvider.add(
        Anniversary(
          id: 'locale-anniversary',
          title: 'Family milestone',
          originDate: DateTime(1990, 6, 3),
          type: AnniversaryType.memorial,
        ),
      );
      addTearDown(countdownProvider.dispose);
      addTearDown(anniversaryProvider.dispose);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => ThemeProvider()),
            ChangeNotifierProvider<CountdownProvider>.value(
              value: countdownProvider,
            ),
            ChangeNotifierProvider<AnniversaryProvider>.value(
              value: anniversaryProvider,
            ),
          ],
          child: MaterialApp(
            home: BrandRouteSurface(
              child: AlmanacScreen(initialDate: DateTime(2026, 6, 2)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip(AlmanacUiCopy.nextDayTooltip));
      await tester.pumpAndSettle();
      expect(find.text('万年历'), findsOneWidget);
      expect(find.text('6月'), findsOneWidget);
      expect(find.text('2026年'), findsOneWidget);
      expect(find.text('四月十八'), findsOneWidget);
      expect(find.text('倒数日 · Release plan'), findsOneWidget);
      expect(find.text('纪念日 · Family milestone'), findsOneWidget);

      final screenState = tester.state(find.byType(AlmanacScreen));
      await tester.tap(
        find.byKey(const ValueKey('selected_date_almanac_summary_card')),
      );
      await tester.pumpAndSettle();

      expect(find.text('2026年6月3日星期三'), findsOneWidget);
      expect(find.text('四月十八'), findsOneWidget);
      expect(find.textContaining('戊申日'), findsOneWidget);

      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      expect(
        tester.state(find.byType(AlmanacScreen, skipOffstage: false)),
        same(screenState),
      );

      expect(find.text('Almanac', skipOffstage: false), findsOneWidget);
      expect(find.textContaining('万年历', skipOffstage: false), findsNothing);
      expect(
        find.textContaining(I18nDateFormat.date(DateTime(2026, 6, 3))),
        findsOneWidget,
      );
      expect(find.text('Month 4, Day 18'), findsOneWidget);
      expect(find.textContaining('戊申日'), findsOneWidget);
      expect(
        find.textContaining('Release plan', skipOffstage: false),
        findsOneWidget,
      );
      expect(
        find.textContaining('Family milestone', skipOffstage: false),
        findsOneWidget,
      );

      I18n.setLocale(AppLocale.zh);
      await tester.pumpAndSettle();
      expect(
        tester.state(find.byType(AlmanacScreen, skipOffstage: false)),
        same(screenState),
      );

      expect(find.text('2026年6月3日星期三'), findsOneWidget);
      expect(find.text('四月十八'), findsOneWidget);
      expect(find.textContaining('戊申日'), findsOneWidget);
      expect(find.text('万年历', skipOffstage: false), findsOneWidget);

      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();

      expect(find.text('6月'), findsOneWidget);
      expect(find.text('四月十八'), findsOneWidget);
      expect(find.text('倒数日 · Release plan'), findsOneWidget);
      expect(find.text('纪念日 · Family milestone'), findsOneWidget);
      expect(find.text('2026年6月3日星期三'), findsNothing);
    },
  );

  test('nullable solar conversion preserves 1899 lunar metadata', () {
    final solarDate = DateTime(1900, 1, 1);

    expect(LunarCalendar.isWithinDocumentedSolarRange(solarDate), isTrue);

    final lunarDate = LunarCalendar.tryFromSolar(solarDate);
    expect(lunarDate, isNotNull);
    expect(lunarDate!.year, 1899);

    final detail = LunarCalendar.tryAlmanacDetail(solarDate);
    expect(detail, isNotNull);
    expect(detail!.solarDate, solarDate);
    expect(detail.lunarDate.year, 1899);
  });
}
