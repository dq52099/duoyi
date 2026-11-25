import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

class RouteRenderProbe {
  RouteRenderProbe(this.tester, this.boundary, this.name);

  final WidgetTester tester;
  final GlobalKey boundary;
  final String name;
  final rows = <Map<String, Object?>>[];
  final errors = <String>[];

  Future<void> reveal(Finder finder) async {
    expect(finder, findsOneWidget);
    final element = tester.element(finder);
    final scroll = Scrollable.maybeOf(element, axis: Axis.vertical);
    if (scroll != null) {
      await scroll.position.ensureVisible(element.findRenderObject()!);
      await tester.pumpAndSettle();
    }
  }

  Future<void> text(
    Finder finder, {
    String? role,
    bool contrast = true,
    bool allowPreviewEllipsis = false,
    double? minimumGeometricScale,
  }) async {
    await reveal(finder);
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: finder, matching: find.byType(RichText)),
    );
    final style = paragraph.text.style!;
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final rect = MatrixUtils.transformRect(
      paragraph.getTransformTo(render),
      Offset.zero & paragraph.size,
    );
    final label = (tester.widget(finder) as Text).data!;
    final incomplete =
        paragraph.didExceedMaxLines ||
        paragraph.textSize.width > paragraph.size.width + 0.1 ||
        paragraph.textSize.height > paragraph.size.height + 0.1;
    if (incomplete && !allowPreviewEllipsis) {
      errors.add('$role $label: incomplete');
    }
    final row = <String, Object?>{
      'role': role,
      'text': label,
      'incomplete': incomplete,
      if (allowPreviewEllipsis) 'intentionalPreview': true,
      'paintedWidth': rect.width,
      'paintedHeight': rect.height,
    };
    if (minimumGeometricScale != null) {
      final geometricScale = math.min(
        rect.width / paragraph.size.width,
        rect.height / paragraph.size.height,
      );
      row['geometricScale'] = geometricScale;
      row['minimumGeometricScale'] = minimumGeometricScale;
      if (geometricScale < minimumGeometricScale) {
        errors.add('$role $label: extra text shrink $geometricScale');
      }
    }
    if (contrast) {
      // The three-pixel blank gap preceding these explicitly chosen paragraphs
      // is within the same card/pill; it avoids glyph pixels and icon boxes.
      final point = Offset(rect.left - 3, rect.center.dy);
      final captured = await tester.runAsync(() async {
        final image = await render.toImage(pixelRatio: 1);
        try {
          final raw = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          final x = point.dx.floor(), y = point.dy.floor();
          expect(x, inInclusiveRange(0, image.width - 1), reason: label);
          expect(y, inInclusiveRange(0, image.height - 1), reason: label);
          final offset = (y * image.width + x) * 4;
          return Color.fromARGB(
            255,
            raw.getUint8(offset),
            raw.getUint8(offset + 1),
            raw.getUint8(offset + 2),
          );
        } finally {
          image.dispose();
        }
      });
      final background = captured!;
      final foreground = style.foreground?.color ?? style.color!;
      final a = Color.alphaBlend(foreground, background).computeLuminance();
      final b = background.computeLuminance();
      final ratio = (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);
      final size = MediaQuery.textScalerOf(
        tester.element(finder),
      ).scale(style.fontSize!);
      final required = size >= 24 ? 3.0 : 4.5;
      row.addAll({
        'foregroundARGB': foreground.toARGB32(),
        'backgroundARGB': background.toARGB32(),
        'sampleX': point.dx.floor(),
        'sampleY': point.dy.floor(),
        'ratio': ratio,
        'required': required,
        'renderedFontSize': size,
      });
      if (ratio < required) {
        errors.add('$role $label: contrast $ratio below $required');
      }
    }
    rows.add(row);
  }

  Future<void> capture(String stage) async {
    final folder = Platform.environment['DUOYI_SECONDARY_SCREENSHOTS'];
    if (folder == null) return;
    await tester.runAsync(() async {
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await render.toImage(pixelRatio: 1);
      try {
        final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        final path = File('$folder/$name-$stage.png');
        path.parent.createSync(recursive: true);
        path.writeAsBytesSync(data.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    });
  }

  Future<void> finish() async {
    final folder = Platform.environment['DUOYI_SECONDARY_MEASUREMENTS'];
    if (folder != null) {
      await tester.runAsync(() async {
        final path = File('$folder/$name.json');
        path.parent.createSync(recursive: true);
        path.writeAsStringSync(
          const JsonEncoder.withIndent(
            '  ',
          ).convert({'name': name, 'measurements': rows, 'errors': errors}),
        );
      });
    }
    expect(tester.takeException(), isNull);
    expect(errors, isEmpty);
  }
}

// Bounded synthetic curve: continuous, monotone, with stronger small-text growth.
class RouteProbeNonlinearScaler extends TextScaler {
  const RouteProbeNonlinearScaler();
  @override
  double scale(double fontSize) =>
      fontSize <= 14 ? fontSize * 1.9 : 26.6 + (fontSize - 14) * 1.4;
  @override
  double get textScaleFactor => 1.9;
}
