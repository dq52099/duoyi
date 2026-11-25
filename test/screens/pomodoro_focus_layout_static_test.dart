import 'dart:io';

import 'package:duoyi/providers/custom_focus_sound_provider.dart';
import 'package:duoyi/providers/focus_room_provider.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/pomodoro_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  test('当前专注保留紧凑布局，受限高度按自然尺寸滚动', () {
    final source = File('lib/screens/pomodoro_screen.dart').readAsStringSync();
    final timerTabSource = source.split('// History tab').first;

    expect(timerTabSource, contains('LayoutBuilder('));
    expect(source, contains('BrandBackground('));
    expect(source, contains('class _PomodoroProviderFallback'));
    expect(source, contains('context.read<PomodoroProvider?>() == null'));
    expect(source, contains('context.read<AuthProvider?>() == null'));
    expect(source, contains('unawaited(_pomodoro.loadFromStorage())'));
    expect(timerTabSource, contains('availableHeight < 660'));
    expect(timerTabSource, contains('availableHeight < 560'));
    expect(timerTabSource, isNot(contains('FittedBox(')));
    expect(timerTabSource, contains('_PomodoroLiveTimer('));
    expect(source, contains('ValueListenableBuilder<int>'));
    expect(source, contains('provider.timerTicks'));
    expect(source, isNot(contains('context.watch<PomodoroProvider>().state')));
    expect(timerTabSource, contains('_FocusControlTile'));
    expect(timerTabSource, contains('SingleChildScrollView('));
    expect(timerTabSource, isNot(contains('ListView(')));
  });

  test('二级路由进入番茄钟时复用外层品牌背景', () {
    for (final path in const [
      'lib/main.dart',
      'lib/screens/mine_screen.dart',
      'lib/screens/today_screen.dart',
      'lib/widgets/calendar_event_sheet.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(
        source,
        isNot(contains('BrandRouteSurface(child: PomodoroScreen()')),
      );
      expect(source, isNot(contains('child: PomodoroScreen()),')));
    }

    expect(
      File('lib/main.dart').readAsStringSync(),
      contains('PomodoroScreen(key: pomodoroKey, useShellBackground: true)'),
    );
    for (final path in const [
      'lib/screens/mine_screen.dart',
      'lib/screens/today_screen.dart',
      'lib/widgets/calendar_event_sheet.dart',
    ]) {
      expect(
        File(path).readAsStringSync(),
        contains('PomodoroScreen(useShellBackground: true)'),
        reason: path,
      );
    }
  });

  test('专注输入弹窗随键盘滚动约束，避免黑屏卡死', () {
    final source = File('lib/screens/pomodoro_screen.dart').readAsStringSync();

    expect(source, contains('class _PomodoroDialogBody'));
    expect(source, contains('media.viewInsets.bottom'));
    expect(source, contains('ScrollViewKeyboardDismissBehavior.onDrag'));
    expect(source, contains('shiftForKeyboard: true'));
    expect(source, contains('content: _PomodoroDialogBody('));
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
          ChangeNotifierProvider(create: (_) => FocusRoomProvider()),
          ChangeNotifierProvider(create: (_) => CustomFocusSoundProvider()),
        ],
        child: const MaterialApp(home: PomodoroScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PomodoroScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('番茄专注独立路由缺少外层 providers 时不黑屏', (tester) async {
    tester.view.physicalSize = const Size(390, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: PomodoroScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('自习室'));
    await tester.pumpAndSettle();

    expect(find.byType(PomodoroScreen), findsOneWidget);
    expect(find.text('好友与全局排行榜'), findsOneWidget);
    final roomTitle = find.text('专注自习室');
    final roomScroll = find.byWidgetPredicate(
      (widget) => widget is Scrollable && widget.axisDirection == AxisDirection.down,
    ).last;
    for (var attempt = 0; attempt < 20 && roomTitle.evaluate().isEmpty; attempt++) {
      await tester.drag(roomScroll, const Offset(0, -220));
      await tester.pumpAndSettle();
      expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 2);
    }
    expect(roomTitle, findsOneWidget);
    final titleElement = tester.element(roomTitle);
    await Scrollable.of(titleElement, axis: Axis.vertical).position.ensureVisible(
      titleElement.findRenderObject()!,
    );
    await tester.pumpAndSettle();
    expect(roomTitle.hitTestable(), findsOneWidget);
    expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 2);
    expect(tester.takeException(), isNull);
  });
}
