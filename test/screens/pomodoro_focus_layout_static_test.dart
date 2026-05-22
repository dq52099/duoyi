import 'dart:io';

import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/pomodoro_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  test('当前专注首屏使用自适应一屏布局，不回退成长滚动卡片', () {
    final source = File('lib/screens/pomodoro_screen.dart').readAsStringSync();
    final timerTabSource = source.split('// History tab').first;

    expect(timerTabSource, contains('LayoutBuilder('));
    expect(timerTabSource, contains('availableHeight < 660'));
    expect(timerTabSource, contains('availableHeight < 560'));
    expect(timerTabSource, contains('FittedBox('));
    expect(timerTabSource, contains('_FocusControlTile'));
    expect(timerTabSource, contains('SingleChildScrollView('));
    expect(timerTabSource, isNot(contains('ListView(')));
  });

  testWidgets('当前专注小屏首屏渲染不产生 overflow', (tester) async {
    tester.view.physicalSize = const Size(390, 620);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => PomodoroProvider()),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ],
        child: const MaterialApp(home: PomodoroScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PomodoroScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
