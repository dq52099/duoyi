import 'dart:ui' show Rect;

import 'package:flutter/painting.dart' show MatrixUtils;
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart' show TextSelection;
import 'package:flutter_test/flutter_test.dart';

bool _isWhitespace(int rune) => (rune >= 9 && rune <= 13) ||
    const [0x20, 0x85, 0xa0, 0x1680, 0x2028, 0x2029, 0x202f, 0x205f, 0x3000].contains(rune) ||
    (rune >= 0x2000 && rune <= 0x200a);

void _inside(Rect actual, Rect container, String reason) {
  expect(actual.left, greaterThanOrEqualTo(container.left - .5), reason: reason);
  expect(actual.top, greaterThanOrEqualTo(container.top - .5), reason: reason);
  expect(actual.right, lessThanOrEqualTo(container.right + .5), reason: reason);
  expect(actual.bottom, lessThanOrEqualTo(container.bottom + .5), reason: reason);
}

/// Validates actual non-whitespace selection ranges against visible containers.
/// Wrap whitespace advances and font leading can extend outside the paragraph's
/// own line box. They do not mean the paragraph clips: the public textSize and
/// didExceedMaxLines determine layout overflow in RenderParagraph. Full copy,
/// scaler, no-transform, semantics and business checks stay with each caller.
void expectHabitTextPaintBounds(
  RenderParagraph paragraph, {
  required Rect cardRect,
  Rect? viewportRect,
  required String reason,
}) {
  expect(paragraph.didExceedMaxLines, isFalse, reason: reason);
  expect(paragraph.textSize.width, lessThanOrEqualTo(paragraph.size.width),
      reason: '$reason: no width overflow can introduce a paragraph clip');
  expect(paragraph.textSize.height, lessThanOrEqualTo(paragraph.size.height),
      reason: '$reason: no height overflow can introduce a paragraph clip');
  final text = paragraph.text.toPlainText();
  final transform = paragraph.getTransformTo(null);
  var offset = 0;
  var nonWhitespaceBoxes = 0;
  int? runStart;
  void checkRun(int start, int end) {
      // Keep ligatures, combining marks and joined emoji in one selection.
      final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: end),
      );
      expect(boxes, isNotEmpty, reason: '$reason: complete non-whitespace run $start..$end');
      for (final box in boxes) {
        final rect = MatrixUtils.transformRect(transform, box.toRect());
        expect(rect.width, greaterThan(0), reason: reason);
        expect(rect.height, greaterThan(0), reason: reason);
        _inside(rect, cardRect, '$reason: complete non-whitespace range inside card');
        if (viewportRect != null) {
          _inside(rect, viewportRect, '$reason: complete non-whitespace range inside viewport');
        }
        nonWhitespaceBoxes++;
      }
  }
  for (final rune in text.runes) {
    final end = offset + (rune > 0xffff ? 2 : 1);
    if (_isWhitespace(rune)) {
      if (runStart != null) {
        checkRun(runStart, offset);
        runStart = null;
      }
    } else {
      runStart ??= offset;
    }
    offset = end;
  }
  if (runStart != null) checkRun(runStart, offset);
  expect(offset, text.length, reason: '$reason: complete UTF-16 traversal');
  if (text.trim().isNotEmpty) {
    expect(nonWhitespaceBoxes, greaterThan(0), reason: reason);
  }
}
