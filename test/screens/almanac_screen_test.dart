import 'package:duoyi/screens/almanac_screen.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('almanac shows date details without weather content', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: AlmanacScreen(initialDate: DateTime(2026, 7, 1))),
    );
    await tester.pumpAndSettle();

    expect(find.text('万年历'), findsWidgets);
    expect(find.text('日期信息'), findsOneWidget);
    expect(find.text('宜'), findsOneWidget);
    expect(find.text('忌'), findsOneWidget);
    final suitableRect = tester.getRect(find.text('宜'));
    final avoidRect = tester.getRect(find.text('忌'));
    expect(
      suitableRect.bottom,
      lessThan(avoidRect.top),
      reason: '宜和忌应上下两行展示，避免在窄屏挤成同一行。',
    );
    expect(find.textContaining('实时天气'), findsNothing);
    expect(find.textContaining('天气参考'), findsNothing);
    expect(find.textContaining('Open-Meteo'), findsNothing);
    expect(find.text('本地天气摘要'), findsNothing);
    expect(find.text('已记录天气'), findsNothing);
    expect(find.text('记录天气'), findsNothing);
  });

  test('almanac suitable and avoid sections stay stacked', () {
    final source = File('lib/screens/almanac_screen.dart').readAsStringSync();
    final start = source.indexOf('Widget _yijiRow');
    final end = source.indexOf('class _DateDetailCard', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final method = source.substring(start, end);

    expect(method, contains('return Column('));
    expect(method, contains("_yijiCard(title: '宜'"));
    expect(method, contains("_yijiCard(title: '忌'"));
    expect(method, contains('const SizedBox(height: 10)'));
    expect(method, isNot(contains('return Row(')));
  });
}
