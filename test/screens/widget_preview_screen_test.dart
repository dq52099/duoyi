import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/screens/widget_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('小组件预览覆盖待办 o 和月历今天按钮', (tester) async {
    final screenshotKey = GlobalKey();
    await tester.binding.setSurfaceSize(const Size(390, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
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
    expect(find.text('o'), findsWidgets);
    expect(find.text('今天'), findsWidgets);

    if (Platform.environment['DUOYI_CAPTURE_WIDGET_SCREENSHOT'] == '1') {
      final boundary =
          screenshotKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = data!.buffer.asUint8List();
      final file = File(
        '.playwright-mcp/ui-regression/widget_preview_todo_calendar.png',
      );
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes);
    }
  });
}
