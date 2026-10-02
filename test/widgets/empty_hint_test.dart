import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:duoyi/widgets/result_states.dart';

void main() {
  group('EmptyHint（卡片内紧凑空态）', () {
    testWidgets('渲染图标与文案', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EmptyHint(icon: Icons.timer_outlined, message: '暂无时间足迹'),
          ),
        ),
      );

      expect(find.text('暂无时间足迹'), findsOneWidget);
      expect(find.byIcon(Icons.timer_outlined), findsOneWidget);
    });

    testWidgets('默认图标为 inbox_outlined，文案居中', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: EmptyHint(message: '暂无数据')),
        ),
      );

      expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
      final text = tester.widget<Text>(find.text('暂无数据'));
      expect(text.textAlign, TextAlign.center);
    });
  });

  group('statistics_screen 接入锚点', () {
    test('统计页卡片空态改用 EmptyHint，裸灰字 Text 清零', () {
      final source = File(
        'lib/screens/statistics_screen.dart',
      ).readAsStringSync();

      expect(source, contains("import '../widgets/result_states.dart';"));
      expect(source, contains('EmptyHint('));

      // 原「裸灰字空态」模式应全部清零（卡片内 Text + Colors.grey）。
      final barePattern = RegExp(
        r"Text\(\s*'暂无[^']*'\s*,\s*style:\s*TextStyle\(color:\s*Colors\.grey\)\s*\)",
      );
      expect(
        barePattern.allMatches(source),
        isEmpty,
        reason: '统计页不应再残留裸灰字空态 Text',
      );
    });

    test('PDF 导出内的 pw.Text 灰字不受影响（PdfColors 非 Flutter Text）', () {
      final source = File(
        'lib/screens/statistics_screen.dart',
      ).readAsStringSync();
      expect(source, contains('pw.Text('));
      expect(source, contains('PdfColors.grey600'));
    });
  });
}
