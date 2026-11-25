import 'dart:ui' as ui;

import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Checks information text/icons against real final raster padding, without
/// requiring button dimensions, tap semantics, or untruncated visual labels.
Future<void> expectInformationChipContrast(
  WidgetTester tester,
  GlobalKey boundary,
  List<String> labels,
) async {
  final semantics = tester.ensureSemantics();
  try {
    await tester.pump();
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final captured = await tester.runAsync(() async {
      final image = await render.toImage(pixelRatio: 1);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        return (data: data!, width: image.width, height: image.height);
      } finally {
        image.dispose();
      }
    });
    expect(captured, isNotNull);
    final pixels = captured!;
    Rect inImage(RenderBox box) => MatrixUtils.transformRect(
      box.getTransformTo(render),
      Offset.zero & box.size,
    );
    for (final label in labels) {
      final metric = find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == label,
      );
      expect(metric, findsOneWidget);
      expect(
        tester.getSemantics(metric).getSemanticsData().label,
        contains(label),
      );
      final text = find.descendant(of: metric, matching: find.text(label));
      final icon = find.descendant(of: metric, matching: find.byType(Icon));
      expect(text, findsOneWidget);
      expect(icon, findsOneWidget);
      final paragraphs = [
        (
          role: 'text',
          paragraph: tester.renderObject<RenderParagraph>(
            find.descendant(of: text, matching: find.byType(RichText)),
          ),
        ),
        (
          role: 'icon',
          paragraph: tester.renderObject<RenderParagraph>(
            find.descendant(of: icon, matching: find.byType(RichText)),
          ),
        ),
      ];
      final chipRect = inImage(tester.renderObject<RenderBox>(metric));
      final contentRect = inImage(
        paragraphs.first.paragraph,
      ).expandToInclude(inImage(paragraphs.last.paragraph));
      // Real blank padding above/below both glyph boxes includes the painted
      // chip, translucent card, and the glass backdrop; no theme-color proxy.
      final paddingY = [
        (chipRect.top + contentRect.top) / 2,
        (contentRect.bottom + chipRect.bottom) / 2,
      ];
      for (final sample in paragraphs) {
        final style = sample.paragraph.text.style;
        final foreground = style?.foreground?.color ?? style?.color;
        expect(foreground, isNotNull);
        final glyphRect = inImage(sample.paragraph);
        for (final y in paddingY) {
          for (final fraction in [0.25, 0.75]) {
            final point = Offset(
              glyphRect.left + glyphRect.width * fraction,
              y,
            );
            expect(chipRect.contains(point), isTrue);
            expect(contentRect.contains(point), isFalse);
            final xPixel = point.dx.floor();
            final yPixel = point.dy.floor();
            expect(xPixel, inInclusiveRange(0, pixels.width - 1));
            expect(yPixel, inInclusiveRange(0, pixels.height - 1));
            final offset = (yPixel * pixels.width + xPixel) * 4;
            final data = pixels.data;
            expect(data.getUint8(offset + 3), 255);
            final background = Color.fromARGB(
              255,
              data.getUint8(offset),
              data.getUint8(offset + 1),
              data.getUint8(offset + 2),
            );
            expect(
              appContrastRatio(
                Color.alphaBlend(foreground!, background),
                background,
              ),
              greaterThanOrEqualTo(4.5),
              reason:
                  '$label ${sample.role}: $foreground on final pixel '
                  '$background at $point',
            );
          }
        }
      }
    }
  } finally {
    semantics.dispose();
  }
}
