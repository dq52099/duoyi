import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Checks every rendered line against its real scroll viewport. Font selection
/// boxes may extend into normal leading outside a paragraph's layout bounds;
/// only the actual ancestor viewport clips them.
Future<void> verifyRetainedDialogText(
  WidgetTester tester,
  Finder finder, {
  required String expected,
}) async {
  expect(finder, findsOneWidget);
  final rich = find.descendant(of: finder, matching: find.byType(RichText));
  final target = rich.evaluate().isEmpty ? finder : rich;
  final element = tester.element(target);
  final paragraph = tester.renderObject<RenderParagraph>(target);
  expect(paragraph.text.toPlainText(), expected);
  expect(paragraph.didExceedMaxLines, isFalse);
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: expected.length),
  );
  expect(boxes, isNotEmpty);
  for (final word in RegExp(
    r"[A-Za-z0-9]+(?:['’-][A-Za-z0-9]+)*",
  ).allMatches(expected)) {
    final wordBoxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: word.start, extentOffset: word.end),
    );
    expect(wordBoxes, isNotEmpty);
    expect(
      wordBoxes.map((box) => box.top.round()).toSet(),
      hasLength(1),
      reason: 'Word ${word.group(0)} must remain on one line',
    );
  }
  final scroll = Scrollable.maybeOf(element);
  final dialog = tester.getRect(find.byType(AlertDialog).first);
  final viewport = scroll == null
      ? dialog
      : tester.getRect(find.byWidget(scroll.widget));
  // Bidi text can have multiple boxes on a line; verify all of them.
  for (final box in boxes) {
    Rect global(ui.TextBox current) => Rect.fromPoints(
      paragraph.localToGlobal(Offset(current.left, current.top)),
      paragraph.localToGlobal(Offset(current.right, current.bottom)),
    );
    if (scroll != null) {
      final delta = global(box).center.dy - viewport.center.dy;
      final position = scroll.position;
      position.jumpTo(
        (position.pixels + delta).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    final actual = global(box);
    expect(actual.left, greaterThanOrEqualTo(viewport.left - 0.5));
    expect(actual.right, lessThanOrEqualTo(viewport.right + 0.5));
    expect(actual.top, greaterThanOrEqualTo(viewport.top - 0.5));
    expect(actual.bottom, lessThanOrEqualTo(viewport.bottom + 0.5));
  }
}
