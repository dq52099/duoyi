import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/screens/widget_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/widget_polish_screenshot_font.dart';

void main() {
  testWidgets('小组件预览覆盖待办 o、月历和目标三档尺寸', (tester) async {
    if (Platform.environment['DUOYI_CAPTURE_WIDGET_SCREENSHOT'] == '1') {
      await tester.runAsync(loadWidgetPolishScreenshotFonts);
    }
    final screenshotKey = GlobalKey();
    await tester.binding.setSurfaceSize(const Size(390, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: widgetPolishScreenshotTheme(),
        home: Scaffold(
          backgroundColor: Colors.white,
          body: RepaintBoundary(
            key: screenshotKey,
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: const [
                    WidgetPreviewCard.todo(
                      displayMode: WidgetDisplayMode.compact,
                    ),
                    SizedBox(height: 12),
                    WidgetPreviewCard.todo(
                      displayMode: WidgetDisplayMode.standard,
                    ),
                    SizedBox(height: 12),
                    WidgetPreviewCard.todo(
                      displayMode: WidgetDisplayMode.detailed,
                    ),
                    SizedBox(height: 16),
                    WidgetPreviewCard.calendar(
                      displayMode: WidgetDisplayMode.compact,
                    ),
                    SizedBox(height: 12),
                    WidgetPreviewCard.calendar(
                      displayMode: WidgetDisplayMode.standard,
                    ),
                    SizedBox(height: 12),
                    WidgetPreviewCard.calendar(
                      displayMode: WidgetDisplayMode.detailed,
                    ),
                    SizedBox(height: 16),
                    WidgetPreviewCard.goal(
                      displayMode: WidgetDisplayMode.compact,
                    ),
                    SizedBox(height: 12),
                    WidgetPreviewCard.goal(
                      displayMode: WidgetDisplayMode.standard,
                    ),
                    SizedBox(height: 12),
                    WidgetPreviewCard.goal(
                      displayMode: WidgetDisplayMode.detailed,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    expect(find.text('○'), findsWidgets);
    expect(find.text('今天'), findsWidgets);
    expect(find.textContaining('发版准备'), findsWidgets);
    expect(find.textContaining('4x3'), findsWidgets);

    if (Platform.environment['DUOYI_CAPTURE_WIDGET_SCREENSHOT'] == '1') {
      await tester.runAsync(() async {
        final boundary =
            screenshotKey.currentContext!.findRenderObject()
                as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        final bytes = data!.buffer.asUint8List();
        image.dispose();
        final file = File(
          'evidence/screenshots/widget-polish-20261006/widget-preview-todo-calendar.png',
        );
        file.parent.createSync(recursive: true);
        file.writeAsBytesSync(bytes);
      });
    }
  });

  testWidgets('小组件预览窄屏 2x2、3x2、4x3 不溢出', (tester) async {
    if (Platform.environment['DUOYI_CAPTURE_WIDGET_SCREENSHOT'] == '1') {
      await tester.runAsync(loadWidgetPolishScreenshotFonts);
    }
    final habitScreenshotKey = GlobalKey();
    await tester.binding.setSurfaceSize(const Size(320, 3600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: widgetPolishScreenshotTheme(),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 3600),
            textScaler: TextScaler.linear(1.6),
          ),
          child: Scaffold(
            backgroundColor: Colors.white,
            body: SingleChildScrollView(
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Column(
                      children: [
                        WidgetPreviewCard.todo(
                          displayMode: WidgetDisplayMode.compact,
                        ),
                        SizedBox(height: 10),
                        WidgetPreviewCard.todo(
                          displayMode: WidgetDisplayMode.standard,
                        ),
                        SizedBox(height: 10),
                        WidgetPreviewCard.todo(
                          displayMode: WidgetDisplayMode.detailed,
                        ),
                        SizedBox(height: 14),
                        WidgetPreviewCard.calendar(
                          displayMode: WidgetDisplayMode.compact,
                        ),
                        SizedBox(height: 10),
                        WidgetPreviewCard.calendar(
                          displayMode: WidgetDisplayMode.standard,
                        ),
                        SizedBox(height: 10),
                        WidgetPreviewCard.calendar(
                          displayMode: WidgetDisplayMode.detailed,
                        ),
                        SizedBox(height: 14),
                        WidgetPreviewCard.goal(
                          displayMode: WidgetDisplayMode.compact,
                        ),
                        SizedBox(height: 10),
                        WidgetPreviewCard.goal(
                          displayMode: WidgetDisplayMode.standard,
                        ),
                        SizedBox(height: 10),
                        WidgetPreviewCard.goal(
                          displayMode: WidgetDisplayMode.detailed,
                        ),
                      ],
                    ),
                  ),
                  RepaintBoundary(
                    key: habitScreenshotKey,
                    child: Container(
                      width: 320,
                      color: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          WidgetPreviewCard.habit(
                            displayMode: WidgetDisplayMode.compact,
                          ),
                          SizedBox(height: 10),
                          WidgetPreviewCard.habit(
                            displayMode: WidgetDisplayMode.standard,
                          ),
                          SizedBox(height: 10),
                          WidgetPreviewCard.habit(
                            displayMode: WidgetDisplayMode.detailed,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    expect(find.text('○'), findsWidgets);
    expect(find.text('今天'), findsWidgets);
    expect(find.textContaining('发版准备'), findsWidgets);
    expect(find.text('今日习惯'), findsWidgets);
    expect(find.text('80%'), findsWidgets);
    expect(find.textContaining('晚间拉伸'), findsWidgets);
    expect(find.textContaining('连续记录 5 天'), findsWidgets);
    expect(find.text('打卡：晚间拉伸'), findsWidgets);

    if (Platform.environment['DUOYI_CAPTURE_WIDGET_SCREENSHOT'] == '1') {
      await tester.runAsync(() async {
        final boundary =
            habitScreenshotKey.currentContext!.findRenderObject()
                as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        final bytes = data!.buffer.asUint8List();
        image.dispose();
        final file = File(
          'evidence/screenshots/widget-polish-20261006/habit-preview-320-1.6.png',
        );
        file.parent.createSync(recursive: true);
        file.writeAsBytesSync(bytes);
      });
    }
  });

  testWidgets('WidgetScreen 支持类型筛选且切换不丢样式，320 宽 1.6 倍字体无溢出', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(320, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: widgetPolishScreenshotTheme(),
        home: const MediaQuery(
          data: MediaQueryData(
            size: Size(320, 2400),
            textScaler: TextScaler.linear(1.6),
          ),
          child: WidgetScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    expect(find.text('小组件样式'), findsOneWidget);
    expect(find.textContaining('示例'), findsWidgets);

    // Initial state is "全部" category
    expect(find.text('桌面查看与完成待办，支持快速记一笔'), findsOneWidget);
    expect(find.text('查看今日完成率、连续记录与快捷打卡'), findsOneWidget);

    // Switch to "效率"
    await tester.tap(find.text('效率'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('桌面查看与完成待办，支持快速记一笔'), findsOneWidget);
    expect(find.text('展示今日专注次数、时长与下一轮计划'), findsOneWidget);
    expect(find.text('查看今日完成率、连续记录与快捷打卡'), findsNothing);

    // Switch to "生活"
    await tester.tap(find.text('生活'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('查看今日完成率、连续记录与快捷打卡'), findsOneWidget);
    expect(find.text('桌面查看与完成待办，支持快速记一笔'), findsNothing);
    expect(find.text('展示今日专注次数、时长与下一轮计划'), findsNothing);

    // Switch display mode to detailed
    await tester.ensureVisible(find.textContaining('详细'));
    await tester.tap(find.textContaining('详细'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final detailedModeSelected = tester
        .widget<SegmentedButton<WidgetDisplayMode>>(
          find.byWidgetPredicate(
            (w) => w is SegmentedButton<WidgetDisplayMode>,
          ),
        );
    expect(detailedModeSelected.selected, {WidgetDisplayMode.detailed});
    expect(find.text(WidgetDisplayMode.detailed.description), findsOneWidget);

    // Switch back to "全部", display mode is preserved
    await tester.ensureVisible(find.text('全部'));
    await tester.tap(find.text('全部'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Category selection scrolls the lazy list; reveal the density panel again.
    final modeFinder = find.byWidgetPredicate(
      (w) => w is SegmentedButton<WidgetDisplayMode>,
    );
    await tester.scrollUntilVisible(
      modeFinder,
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    final modeAfterCategorySwitch = tester
        .widget<SegmentedButton<WidgetDisplayMode>>(modeFinder);
    expect(modeAfterCategorySwitch.selected, {WidgetDisplayMode.detailed});
    expect(find.text(WidgetDisplayMode.detailed.description), findsOneWidget);
    expect(find.text(WidgetDisplayMode.compact.description), findsNothing);
    expect(find.text(WidgetDisplayMode.standard.description), findsNothing);

    await tester.scrollUntilVisible(
      find.text('桌面查看与完成待办，支持快速记一笔'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('桌面查看与完成待办，支持快速记一笔'), findsOneWidget);
    expect(find.text('查看今日完成率、连续记录与快捷打卡'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
