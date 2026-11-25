import 'dart:io';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/i18n_date_format.dart';
import 'package:duoyi/screens/almanac_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppLocale originalLocale;
  setUp(() {
    originalLocale = I18n.current;
    I18n.setLocale(AppLocale.zh);
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => I18n.setLocale(originalLocale));

  testWidgets('today feedback follows locale while visible', (tester) async {
    await _mount(tester, DateTime(2026, 6, 3));
    await tester.tap(find.byTooltip('回到今天'));
    await tester.pumpAndSettle();
    expect(find.text('已回到今天'), findsOneWidget);
    I18n.setLocale(AppLocale.en);
    await tester.pump();
    expect(find.text('Returned to today'), findsOneWidget);
    expect(find.text('已回到今天'), findsNothing);
  });

  testWidgets('opened hour fortune keeps raw fields while labels switch', (
    tester,
  ) async {
    await _mount(tester, DateTime(2026, 6, 3));
    await _openDetail(tester);
    await tester.ensureVisible(find.text('子'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('子'));
    await tester.pumpAndSettle();
    final dialog = tester.element(find.byType(Dialog));
    expect(find.text('子时 · 吉'), findsOneWidget);
    expect(find.text('壬子'), findsOneWidget);
    I18n.setLocale(AppLocale.en);
    await tester.pumpAndSettle();
    expect(identical(tester.element(find.byType(Dialog)), dialog), isTrue);
    expect(find.text('Time'), findsOneWidget);
    expect(find.text('Got it'), findsOneWidget);
    expect(find.text('时间'), findsNothing);
    expect(find.text('壬子'), findsOneWidget);
    expect(find.text('青龙'), findsOneWidget);
    expect(find.text('23:00-00:59'), findsOneWidget);
    I18n.setLocale(AppLocale.zh);
    await tester.pumpAndSettle();
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('date picker keeps its wheel state and live title', (
    tester,
  ) async {
    await _mount(tester, DateTime(2026, 6, 3));
    await tester.tap(find.byTooltip('选择日期').first);
    await tester.pumpAndSettle();
    // Solar mode uses the month grid. Keep the sheet mounted while the
    // locale changes so its selected day and title are projected in place.
    expect(find.text('2026年6月'), findsOneWidget);
    I18n.setLocale(AppLocale.en);
    await tester.pumpAndSettle();
    expect(find.text('Almanac'), findsWidgets);
    expect(find.text('万年历'), findsNothing);
    await tester.tap(find.text(I18n.tr('action.confirm')));
    await tester.pumpAndSettle();
    expect(find.text('Almanac'), findsOneWidget);
    expect(find.byTooltip('Select date'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'detail civil paging survives DST and retains controller on locale',
    (tester) async {
      await _mount(tester, DateTime(2026, 3, 7));
      await _openDetail(tester);
      final controller = tester
          .widget<PageView>(find.byType(PageView))
          .controller!;
      final start = controller.page!.round();
      for (var offset = 1; offset <= 3; offset++) {
        controller.jumpToPage(start + offset);
        await tester.pumpAndSettle();
        final day = DateTime(2026, 3, 7 + offset);
        expect(
          find.textContaining('${day.year}年${day.month}月${day.day}日星期'),
          findsOneWidget,
        );
      }
      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      expect(
        identical(
          tester.widget<PageView>(find.byType(PageView)).controller,
          controller,
        ),
        isTrue,
      );
      expect(controller.page, start + 3);
      expect(
        find.textContaining(I18nDateFormat.date(DateTime(2026, 3, 10))),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Mar'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('December civil slots never borrow a skipped day', (
    tester,
  ) async {
    final apia = Platform.environment['TZ'] == 'Pacific/Apia';
    await _mount(tester, DateTime(2011, 12, 29));
    await _openDetail(tester);
    final controller = tester
        .widget<PageView>(find.byType(PageView))
        .controller!;
    final start = controller.page!.round();
    controller.jumpToPage(start + 1);
    await tester.pumpAndSettle();
    expect(find.textContaining('2011年12月30日'), findsWidgets);
    expect(find.textContaining('2011年12月29日星期'), findsNothing);
    if (apia) {
      expect(DateTime(2011, 12, 30).day, 31);
      expect(find.textContaining('暂不可用'), findsWidgets);
      expect(find.text('胎神'), findsNothing);
      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      expect(
        find.textContaining(RegExp('unavailable', caseSensitive: false)),
        findsWidgets,
      );
      I18n.setLocale(AppLocale.zh);
      await tester.pumpAndSettle();
    } else {
      expect(find.text('胎神'), findsOneWidget);
    }
    controller.jumpToPage(start + 2);
    await tester.pumpAndSettle();
    expect(find.textContaining('2011年12月31日星期'), findsOneWidget);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('12月'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _mount(WidgetTester tester, DateTime date) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: AlmanacScreen(initialDate: date)));
  await tester.pumpAndSettle();
}

Future<void> _openDetail(WidgetTester tester) async {
  await tester.tap(
    find.byKey(const ValueKey('selected_date_almanac_summary_card')),
  );
  await tester.pumpAndSettle();
}
