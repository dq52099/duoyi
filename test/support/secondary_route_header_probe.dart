import 'package:duoyi/core/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'secondary_route_render_probe.dart';

/// Checks the actual AppBar paragraph and controls in a pushed production route.
Future<void> checkSecondaryRouteHeader(
  RouteRenderProbe probe,
  String titleKey, {
  required String stage,
}) async {
  final tester = probe.tester;
  final appBar = find.byType(AppBar);
  expect(appBar, findsOneWidget);
  final title = find.descendant(
    of: appBar,
    matching: find.text(I18n.tr(titleKey)),
  );
  await probe.text(title, role: '$stage route title', minimumGeometricScale: 1);
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: title, matching: find.byType(RichText)),
  );
  final barRect = tester.getRect(appBar);
  final titleRect = tester.getRect(title);
  final style = paragraph.text.style!;
  final controls = <Map<String, Object?>>[];
  for (final element
      in find
          .descendant(of: appBar, matching: find.byType(IconButton))
          .evaluate()) {
    final finder = find.byElementPredicate((e) => identical(e, element));
    final rect = tester.getRect(finder);
    expect(finder.hitTestable(), findsOneWidget);
    controls.add({
      'left': rect.left,
      'top': rect.top,
      'width': rect.width,
      'height': rect.height,
    });
    if (titleRect.overlaps(rect)) {
      probe.errors.add('$stage route title overlaps toolbar control');
    }
    expect(rect.top, greaterThanOrEqualTo(barRect.top - .1));
    expect(rect.bottom, lessThanOrEqualTo(barRect.bottom + .1));
  }
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: I18n.tr(titleKey).length),
  );
  for (final box in boxes) {
    final top = paragraph.localToGlobal(Offset(box.left, box.top));
    final bottom = paragraph.localToGlobal(Offset(box.right, box.bottom));
    if (top.dy < barRect.top - .1 ||
        bottom.dy > barRect.bottom + .1 ||
        top.dx < -.1 ||
        bottom.dx > tester.view.physicalSize.width + .1) {
      probe.errors.add('$stage route title glyphs outside toolbar/viewport');
    }
  }
  for (final word in RegExp(r'[A-Za-z]+').allMatches(I18n.tr(titleKey))) {
    final wordBoxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: word.start, extentOffset: word.end),
    );
    if (wordBoxes.map((box) => box.top).toSet().length > 1) {
      probe.errors.add('$stage route title splits word ${word.group(0)}');
    }
  }
  probe.rows.last.addAll({
    'nominalFontSize': style.fontSize,
    'fontWeight': style.fontWeight?.value,
    'toolbarHeight': barRect.height,
    'titleWidth': titleRect.width,
    'controls': controls,
  });
}
