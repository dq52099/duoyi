import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/widgets/empty_state.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/widget_polish_screenshot_font.dart';

void main() {
  for (final width in [320.0, 390.0]) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('Todo and Habit empty cards align at $width / $scale', (
        tester,
      ) async {
        if (Platform.environment['DUOYI_CAPTURE_EMPTY_SCREENSHOT'] == '1') {
          await tester.runAsync(loadWidgetPolishScreenshotFonts);
        }
        await tester.binding.setSurfaceSize(Size(width * 2, 600));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final captureKey = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: widgetPolishScreenshotTheme(),
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                backgroundColor: Colors.white,
                body: RepaintBoundary(
                  key: captureKey,
                  child: Row(
                    children: [
                      SizedBox(
                        width: width,
                        child: EmptyState(
                          key: const ValueKey('todo'),
                          icon: Icons.check_circle_outline,
                          message: '暂无待办任务',
                          actionLabel: '添加第一个任务',
                          onAction: () {},
                          minCardHeight: EmptyState.defaultMinCardHeight,
                        ),
                      ),
                      SizedBox(
                        width: width,
                        child: SingleChildScrollView(
                          child: EmptyState(
                            key: const ValueKey('habit'),
                            icon: Icons.repeat,
                            message: '今天没有习惯任务',
                            actionLabel: '添加习惯',
                            onAction: () {},
                            minCardHeight: EmptyState.defaultMinCardHeight,
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
        await tester.pumpAndSettle();
        final todo = tester.getSize(
          find.descendant(
            of: find.byKey(const ValueKey('todo')),
            matching: find.byType(AppSurfaceCard),
          ),
        );
        final habit = tester.getSize(
          find.descendant(
            of: find.byKey(const ValueKey('habit')),
            matching: find.byType(AppSurfaceCard),
          ),
        );
        expect(todo.width, habit.width);
        expect(todo.height, habit.height);
        expect(tester.takeException(), isNull);
        if (Platform.environment['DUOYI_CAPTURE_EMPTY_SCREENSHOT'] == '1') {
          await tester.runAsync(() async {
            final boundary =
                captureKey.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final picture = await boundary.toImage(pixelRatio: 1);
            final bytes = await picture.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File(
              'evidence/screenshots/widget-polish-20261006/empty-cards-${width.toInt()}-$scale.png',
            );
            file.parent.createSync(recursive: true);
            file.writeAsBytesSync(bytes!.buffer.asUint8List());
            picture.dispose();
          });
        }
      });
    }
  }
}
