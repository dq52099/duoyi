import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'rendered_control_contrast.dart';
import 'weekly_review_screenshot_font.dart';

const retainedFeedbackCaptureKey = ValueKey('retained-feedback-capture');

Future<void> loadRetainedFeedbackFonts() => loadWeeklyReviewScreenshotFonts();

/// Measure the actual retained message and action under production theme data.
/// Optional screenshots include the Navigator overlays and the whole viewport.
Future<void> verifyRetainedFeedbackVisual(
  WidgetTester tester, {
  required String screen,
  required String brand,
  required String caseName,
  required String message,
  String? action,
}) async {
  final snack = find.byType(SnackBar);
  final text = find.descendant(of: snack, matching: find.text(message));
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: text, matching: find.byType(RichText)),
  );
  expect(paragraph.didExceedMaxLines, isFalse);
  expect(
    paragraph.textSize.width,
    lessThanOrEqualTo(paragraph.size.width + .1),
  );
  expect(
    paragraph.textSize.height,
    lessThanOrEqualTo(paragraph.size.height + .1),
  );
  final viewport =
      Offset.zero & (tester.view.physicalSize / tester.view.devicePixelRatio);
  final rect = tester.getRect(text);
  expect(viewport.inflate(.1).contains(rect.topLeft), isTrue);
  expect(viewport.inflate(.1).contains(rect.bottomRight), isTrue);
  if (action != null) {
    final label = find.descendant(of: snack, matching: find.text(action));
    final button = find
        .ancestor(
          of: label,
          matching: find.byWidgetPredicate(
            (widget) => widget is ButtonStyleButton,
          ),
        )
        .first;
    expectReadableControl(tester, button);
  }
  if (Platform.environment['DUOYI_CAPTURE_RETAINED_FEEDBACK'] != '1') return;
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(retainedFeedbackCaptureKey),
    );
    final picture = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
      final file = File(
        'evidence/screenshots/retained-feedback-20261020/'
        '$screen-$brand-$caseName-${I18n.current.name}.png',
      );
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      picture.dispose();
    }
  });
}
